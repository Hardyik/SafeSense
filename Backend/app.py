from flask import Flask, request, jsonify, send_from_directory
from flask_cors import CORS
import mysql.connector
from mysql.connector import Error
import os
import json
import uuid
import re
from pathlib import Path
from dotenv import load_dotenv
from datetime import datetime, timedelta
import tempfile
import traceback
import bcrypt
import jwt
import functools
import shutil

# Load environment variables — find .env next to this script
dotenv_path = Path(__file__).parent / '.env'
if dotenv_path.exists():
    load_dotenv(dotenv_path=dotenv_path)
    print(f"✓ Loaded .env from {dotenv_path}")
else:
    load_dotenv()
    print(f"⚠ .env not found at {dotenv_path}, using system env vars")

app = Flask(__name__)
CORS(app, resources={
    # /api/* — the JSON API (browser sends Authorization + JSON bodies)
    r"/api/*": {
        "origins": "*",
        "allow_headers": ["Authorization", "Content-Type"],
        "methods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    },
    # /uploads/* — report photos are loaded by Image.network from the
    # Flutter web app; without CORS headers the browser blocks them and
    # Image.network fails with "statusCode: 0". (Native Android/iOS don't
    # enforce CORS, but web does — cover both.)
    r"/uploads/*": {"origins": "*", "methods": ["GET", "OPTIONS"]},
})

# ========== CONFIGURATION ==========
DB_HOST = os.getenv('DB_HOST', 'localhost')
DB_USER = os.getenv('DB_USER', 'root')
DB_PASSWORD = os.getenv('DB_PASSWORD', '')
DB_NAME = os.getenv('DB_NAME', 'safesense')
JWT_SECRET = os.getenv('JWT_SECRET', os.urandom(32).hex())
JWT_EXPIRY_HOURS = int(os.getenv('JWT_EXPIRY_HOURS', '24'))

# Uploads: images are stored under Backend/uploads/ and served at
# GET /uploads/<filename>. image_url in the DB is the relative path
# 'uploads/<filename>' so it works across any host/port.
BASE_DIR = Path(__file__).parent
UPLOAD_DIR = BASE_DIR / 'uploads'
UPLOAD_DIR.mkdir(exist_ok=True)

# First admin auto-seed (runs at startup, before serving requests).
ADMIN_EMAIL = os.getenv('ADMIN_EMAIL', '')
ADMIN_PASSWORD = os.getenv('ADMIN_PASSWORD', '')

# Try to import YOLOv8, but don't crash if not installed
try:
    from ultralytics import YOLO
    YOLO_AVAILABLE = True

    MODEL_DIR = Path(__file__).parent / 'ai_model'
    YOLO_MODELS = {
        'flood': YOLO(str(MODEL_DIR / 'flood_best.pt')),
        'hazard': YOLO(str(MODEL_DIR / 'hazard_best.pt')),
        'fire_building': YOLO(str(MODEL_DIR / 'hazard_fire_building_best.pt')),
    }
    print(f"✓ YOLO models loaded: {list(YOLO_MODELS.keys())}")
    for name, m in YOLO_MODELS.items():
        print(f"  - {name}: classes = {m.names}")
except ImportError:
    YOLO_AVAILABLE = False
    MODEL_DIR = Path(__file__).parent / 'ai_model'
    print("⚠ YOLOv8 not installed. Install with: pip install ultralytics opencv-python")
except Exception as e:
    YOLO_AVAILABLE = False
    MODEL_DIR = Path(__file__).parent / 'ai_model'
    print(f"⚠ YOLO warning: {e}")

# Teachable Machine classifier — fast first-pass check across 6 categories
# (Earthquake, Smoke, Normal, Landslide, Flood, Fire)
try:
    from tensorflow.keras.models import load_model
    from PIL import Image, ImageOps
    import numpy as np

    TM_MODEL = load_model(str(MODEL_DIR / 'keras_model.h5'), compile=False)
    with open(MODEL_DIR / 'labels.txt', 'r') as f:
        TM_CLASS_NAMES = [line.strip() for line in f.readlines()]
    TM_AVAILABLE = True
    print(f"✓ Teachable Machine classifier loaded: {TM_CLASS_NAMES}")
except Exception as e:
    TM_AVAILABLE = False
    print(f"⚠ Teachable Machine model not loaded: {e}")

# ========== DATABASE HELPERS ==========
def get_db_connection():
    """Get a fresh database connection"""
    try:
        connection = mysql.connector.connect(
            host=DB_HOST,
            user=DB_USER,
            password=DB_PASSWORD,
            database=DB_NAME,
            autocommit=True
        )
        return connection
    except Error as e:
        print(f"❌ Database connection error: {e}")
        return None

def query_db(sql, params=None, fetch=True):
    """Execute a query and return results"""
    conn = get_db_connection()
    if not conn:
        return None
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(sql, params or ())
        if fetch:
            result = cursor.fetchall()
        else:
            conn.commit()
            result = cursor.rowcount
        return result
    except Error as e:
        print(f"❌ Database error: {e}")
        traceback.print_exc()
        return None
    finally:
        if conn and conn.is_connected():
            cursor.close()
            conn.close()

def execute_db(sql, params=None):
    """Execute an INSERT and return the new row's auto-increment ID (or
    None on failure). query_db(fetch=False) only gives rowcount, which
    isn't enough when the client needs the created row back."""
    conn = get_db_connection()
    if not conn:
        return None
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(sql, params or ())
        conn.commit()
        return cursor.lastrowid
    except Error as e:
        print(f"❌ Database error: {e}")
        traceback.print_exc()
        return None
    finally:
        if conn and conn.is_connected():
            cursor.close()
            conn.close()

# ========== JWT AUTH ==========
def generate_token(user_id, email):
    """Generate a JWT token for a user"""
    payload = {
        'user_id': user_id,
        'email': email,
        'exp': datetime.utcnow() + timedelta(hours=JWT_EXPIRY_HOURS),
        'iat': datetime.utcnow()
    }
    return jwt.encode(payload, JWT_SECRET, algorithm='HS256')

def require_auth(f):
    """Decorator to require a valid JWT token"""
    @functools.wraps(f)
    def decorated(*args, **kwargs):
        token = None
        auth_header = request.headers.get('Authorization', '')
        if auth_header.startswith('Bearer '):
            token = auth_header[7:]

        if not token:
            return jsonify({'error': 'Authentication required'}), 401

        try:
            payload = jwt.decode(token, JWT_SECRET, algorithms=['HS256'])
            request.user_id = payload['user_id']
            request.user_email = payload['email']
        except jwt.ExpiredSignatureError:
            return jsonify({'error': 'Token expired'}), 401
        except jwt.InvalidTokenError:
            return jsonify({'error': 'Invalid token'}), 401

        return f(*args, **kwargs)
    return decorated

def require_admin(f):
    """require_auth + role check against the user table. The role is read
    fresh from MySQL on every admin request — no trusted claims baked into
    the token, so demoting an admin takes effect immediately."""
    @functools.wraps(f)
    def decorated(*args, **kwargs):
        token = None
        auth_header = request.headers.get('Authorization', '')
        if auth_header.startswith('Bearer '):
            token = auth_header[7:]
        if not token:
            return jsonify({'error': 'Authentication required'}), 401
        try:
            payload = jwt.decode(token, JWT_SECRET, algorithms=['HS256'])
        except jwt.ExpiredSignatureError:
            return jsonify({'error': 'Token expired'}), 401
        except jwt.InvalidTokenError:
            return jsonify({'error': 'Invalid token'}), 401

        rows = query_db("SELECT role FROM user WHERE user_id = %s", (payload['user_id'],))
        if not rows or rows[0].get('role') != 'admin':
            return jsonify({'error': 'Admin access required'}), 403
        request.user_id = payload['user_id']
        request.user_email = payload['email']
        return f(*args, **kwargs)
    return decorated

# ======== ADMIN SEED (first admin, from .env) ========
def seed_first_admin():
    """Create the first admin account at startup so you can promote other
    users from the app. Both ADMIN_EMAIL and ADMIN_PASSWORD must be set in
    .env; nothing happens otherwise (and nothing is logged beyond a note)."""
    if not ADMIN_EMAIL or not ADMIN_PASSWORD:
        return
    try:
        existing = query_db("SELECT user_id, role FROM user WHERE email = %s", (ADMIN_EMAIL,))
        if existing:
            if existing[0].get('role') != 'admin':
                query_db("UPDATE user SET role = 'admin' WHERE user_id = %s",
                         (existing[0]['user_id'],), fetch=False)
                print(f"✓ Elevated existing user {ADMIN_EMAIL} to admin")
            return
        password_hash = bcrypt.hashpw(ADMIN_PASSWORD.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
        execute_db(
            "INSERT INTO user (name, email, phone, password_hash, role) VALUES (%s, %s, %s, %s, 'admin')",
            ('Local Admin', ADMIN_EMAIL, '', password_hash),
        )
        print(f"✓ Seeded first admin: {ADMIN_EMAIL}")
    except Exception as e:
        print(f"⚠ Admin seed failed: {e}")


# ========== HAZARD DETECTION ==========
# Map each model's class names -> (hazard_level, road_status)
CLASS_INFO = {
    # flood_best.pt
    'flood':              {'hazard_level': 'danger',   'road_status': 'Blocked'},

    # hazard_best.pt — trained specifically on earthquake damage
    'hazard':              {'hazard_level': 'danger',   'road_status': 'Structural damage — avoid area'},

    # hazard_fire_building_best.pt
    'fire':                {'hazard_level': 'danger',   'road_status': 'Blocked'},
    'collapsed_building':  {'hazard_level': 'danger',   'road_status': 'Blocked'},

    # Teachable Machine classifier — categories not covered by the YOLO models
    'earthquake':          {'hazard_level': 'danger',   'road_status': 'Structural damage — avoid area'},
    'smoke':                {'hazard_level': 'moderate', 'road_status': 'Reduced visibility — proceed with caution'},
    'landslide':            {'hazard_level': 'danger',   'road_status': 'Blocked'},
}

def classify_with_teachable_machine(image_path):
    """
    Runs the Teachable Machine Keras classifier on the image.
    Returns (label_lowercase, confidence) or (None, 0.0) if unavailable.
    Labels file lines look like '0 Earthquake', so we strip the index prefix.
    """
    if not TM_AVAILABLE:
        return None, 0.0
    try:
        data = np.ndarray(shape=(1, 224, 224, 3), dtype=np.float32)
        image = Image.open(image_path).convert("RGB")
        image = ImageOps.fit(image, (224, 224), Image.Resampling.LANCZOS)
        image_array = np.asarray(image)
        normalized_image_array = (image_array.astype(np.float32) / 127.5) - 1
        data[0] = normalized_image_array

        prediction = TM_MODEL.predict(data, verbose=0)
        index = np.argmax(prediction)
        raw_label = TM_CLASS_NAMES[index]
        # Strip leading index like "0 " from "0 Earthquake"
        label = raw_label.split(' ', 1)[-1].strip().lower() if ' ' in raw_label else raw_label.strip().lower()
        confidence = float(prediction[0][index])
        return label, confidence
    except Exception as e:
        print(f"⚠ Teachable Machine classify error: {e}")
        traceback.print_exc()
        return None, 0.0

def analyze_damage_with_yolo(image_path):
    """
    Fast first pass: Teachable Machine classifier.
    If it confidently says "normal", skip YOLO entirely and return safe
    (big speed win for the common case where nothing's actually wrong).
    Otherwise, run all trained YOLO models too and keep whichever single
    result (YOLO or Teachable Machine) is more confident.
    """
    tm_label, tm_conf = classify_with_teachable_machine(image_path)

    if tm_label == 'normal' and tm_conf > 0.6:
        return {
            'damage_type': 'none',
            'hazard_level': 'safe',
            'confidence': round(tm_conf, 2),
            'road_status': 'Clear'
        }

    if not YOLO_AVAILABLE:
        # Fall back to whatever the Teachable Machine classifier found,
        # since YOLO isn't available to double-check.
        if tm_label:
            info = CLASS_INFO.get(tm_label, {'hazard_level': 'moderate', 'road_status': 'Unknown'})
            return {
                'damage_type': tm_label,
                'hazard_level': info['hazard_level'],
                'confidence': round(tm_conf, 2),
                'road_status': info['road_status']
            }
        return {
            'damage_type': 'flood',
            'hazard_level': 'moderate',
            'confidence': 0.65,
            'road_status': 'Partially blocked'
        }

    try:
        best_label = None
        best_conf = 0.0

        for model_name, model in YOLO_MODELS.items():
            results = model.predict(image_path, conf=0.4, verbose=False)
            for r in results:
                if r.boxes is None or len(r.boxes) == 0:
                    continue
                for box in r.boxes:
                    conf = float(box.conf[0])
                    cls_id = int(box.cls[0])
                    label = model.names[cls_id]
                    if conf > best_conf:
                        best_conf = conf
                        best_label = label.lower()

        # Fold in the Teachable Machine result as one more candidate,
        # unless it's the (already-handled) "normal" case.
        if tm_label and tm_label != 'normal' and tm_conf > best_conf:
            best_conf = tm_conf
            best_label = tm_label

        if best_label is None:
            # No detections above threshold from YOLO, and Teachable
            # Machine didn't find anything confident either.
            return {
                'damage_type': 'none',
                'hazard_level': 'safe',
                'confidence': 0.0,
                'road_status': 'Clear'
            }

        info = CLASS_INFO.get(best_label, {'hazard_level': 'moderate', 'road_status': 'Unknown'})

        return {
            'damage_type': best_label,
            'hazard_level': info['hazard_level'],
            'confidence': round(best_conf, 2),
            'road_status': info['road_status']
        }

    except Exception as e:
        print(f"⚠ YOLO error: {e}")
        traceback.print_exc()
        return {
            'damage_type': 'unknown',
            'hazard_level': 'moderate',
            'confidence': 0.5,
            'road_status': 'Unknown'
        }

# ========== ROUTES ==========

@app.route('/')
def home():
    return jsonify({
        "message": "SafeSense Backend is running!",
        "status": "OK",
        "version": "1.0.0",
        "yolo_available": YOLO_AVAILABLE,
        "teachable_machine_available": TM_AVAILABLE
    })

@app.route('/test-db')
def test_db():
    """Test database connection"""
    connection = get_db_connection()
    if connection and connection.is_connected():
        connection.close()
        return jsonify({
            "message": "Database connected successfully!",
            "status": "OK"
        }), 200
    else:
        return jsonify({
            "message": "Failed to connect to database",
            "status": "ERROR",
            "help": "Make sure MySQL is running and .env has correct credentials"
        }), 500

# ========== USER AUTHENTICATION ==========

@app.route('/api/auth/login', methods=['POST'])
def login():
    """User login with JWT token"""
    try:
        data = request.json
        email = data.get('email')
        password = data.get('password')

        if not email or not password:
            return jsonify({"error": "Email and password required"}), 400

        # Fetch user by email only
        user = query_db(
            "SELECT user_id, email, name, password_hash FROM user WHERE email = %s",
            (email,)
        )

        if not user:
            return jsonify({"error": "Invalid credentials"}), 401

        # Verify password — handle both plaintext (legacy) and bcrypt hashes
        stored_hash = user[0]['password_hash']
        is_bcrypt = isinstance(stored_hash, str) and stored_hash.startswith('$2')

        if is_bcrypt:
            # Normal bcrypt verification
            if isinstance(stored_hash, str):
                stored_hash = stored_hash.encode('utf-8')
            if not bcrypt.checkpw(password.encode('utf-8'), stored_hash):
                return jsonify({"error": "Invalid credentials"}), 401
        else:
            # Legacy plaintext password — compare directly
            if stored_hash != password:
                return jsonify({"error": "Invalid credentials"}), 401
            # Auto-upgrade: hash the plaintext password and save it
            new_hash = bcrypt.hashpw(
                password.encode('utf-8'),
                bcrypt.gensalt()
            ).decode('utf-8')
            query_db(
                "UPDATE user SET password_hash = %s WHERE user_id = %s",
                (new_hash, user[0]['user_id']),
                fetch=False
            )
            print(f"✓ Auto-hashed password for user {user[0]['email']}")

        # Generate JWT token
        token = generate_token(user[0]['user_id'], user[0]['email'])

        return jsonify({
            "status": "success",
            "user": {
                "id": user[0]['user_id'],
                "email": user[0]['email'],
                "name": user[0]['name']
            },
            "token": token
        }), 200
    except Exception as e:
        print(f"Login error: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/auth/register', methods=['POST'])
def register():
    """User registration with hashed password"""
    try:
        data = request.json
        email = data.get('email')
        password = data.get('password')
        name = data.get('name')
        phone = data.get('phone')

        if not email or not password:
            return jsonify({"error": "Email and password required"}), 400

        if len(password) < 6:
            return jsonify({"error": "Password must be at least 6 characters"}), 400

        # Check if email already exists
        existing = query_db(
            "SELECT user_id FROM user WHERE email = %s",
            (email,)
        )
        if existing:
            return jsonify({"error": "Email already registered"}), 409

        # Hash password with bcrypt
        password_hash = bcrypt.hashpw(
            password.encode('utf-8'),
            bcrypt.gensalt()
        ).decode('utf-8')

        result = query_db(
            "INSERT INTO user (email, password_hash, name, phone) VALUES (%s, %s, %s, %s)",
            (email, password_hash, name, phone or ''),
            fetch=False
        )

        if result and result > 0:
            # Auto-login: return a token + user object like login() does, so
            # the app can go straight to Home instead of back to Login.
            new_user = query_db("SELECT user_id, email, name FROM user WHERE email = %s", (email,))
            token = generate_token(new_user[0]['user_id'], new_user[0]['email'])
            return jsonify({
                "status": "success",
                "message": "User registered",
                "user": {
                    "id": new_user[0]['user_id'],
                    "email": new_user[0]['email'],
                    "name": new_user[0]['name'],
                },
                "token": token,
            }), 201
        else:
            return jsonify({"error": "Registration failed"}), 400
    except Exception as e:
        print(f"Register error: {e}")
        return jsonify({"error": str(e)}), 500

# ========== HAZARD REPORTS ==========

@app.route('/api/reports/upload', methods=['POST'])
@require_auth
def upload_report():
    """
    Upload an image, analyze with the Teachable Machine classifier and
    YOLOv8 models, store report in database.
    Inserts into: uploaded_image + detection_result (+ optionally disaster).
    """
    try:
        print("🔵 [1] Route entered")

        if 'image' not in request.files:
            return jsonify({"error": "No image provided"}), 400
        print("🔵 [2] Image found in request")

        file = request.files['image']
        latitude = float(request.form.get('latitude', 19.2456))
        longitude = float(request.form.get('longitude', 73.1300))
        user_id = request.user_id
        print(f"🔵 [3] Parsed form data: lat={latitude}, lng={longitude}, user_id={user_id}")

        with tempfile.NamedTemporaryFile(suffix='.jpg', delete=False) as tmp:
            file.save(tmp.name)
            image_path = tmp.name
        print(f"🔵 [4] Saved temp file at {image_path}")

        analysis = analyze_damage_with_yolo(image_path)
        print(f"🔵 [5] Analysis complete: {analysis}")

        # Move the image into uploads/ with a uuid name. The DB stores the
        # relative path ('uploads/<name>.jpg') and GET /uploads/<name>
        # serves it, so URLs survive host/port changes (LAN phone → PC).
        rel_path = None
        try:
            ext = os.path.splitext(file.filename or '')[1] or '.jpg'
            if not re.fullmatch(r'\.(jpg|jpeg|png|webp)', ext, re.IGNORECASE):
                ext = '.jpg'
            filename = f"{uuid.uuid4().hex}{ext}"
            shutil.move(image_path, str(UPLOAD_DIR / filename))
            rel_path = f"uploads/{filename}"
        except Exception as e:
            print(f"⚠ Could not move upload into {UPLOAD_DIR}: {e}")
        print(f"🔵 [5b] Stored as {rel_path}")

        user_description = request.form.get('description', '')
        description = user_description if user_description else f"Auto-detected: {analysis['damage_type']} - {analysis['road_status']}"
        print("🔵 [6] Description built, starting DB transaction")

        conn = get_db_connection()
        if not conn:
            print("🔴 [ERROR] DB connection failed")
            return jsonify({"error": "Database connection failed"}), 500
        print("🔵 [7] DB connected")

        try:
            cursor = conn.cursor(dictionary=True)

            cursor.execute(
                """
                INSERT INTO disaster (type, severity, description, start_time, status)
                VALUES (%s, %s, %s, NOW(), 'active')
                """,
                (analysis['damage_type'], analysis['hazard_level'], description),
            )
            disaster_id = cursor.lastrowid
            print(f"🔵 [8] Disaster inserted, id={disaster_id}")

            cursor.execute(
                """
                INSERT INTO uploaded_image (user_id, disaster_id, image_url, description, latitude, longitude, status)
                VALUES (%s, %s, %s, %s, %s, %s, 'pending')
                """,
                (user_id, disaster_id, rel_path, user_description, latitude, longitude),
            )
            image_id = cursor.lastrowid
            print(f"🔵 [9] Image row inserted, id={image_id}")

            cursor.execute(
                """
                INSERT INTO detection_result (image_id, damage_type, severity, confidence, road_status)
                VALUES (%s, %s, %s, %s, %s)
                """,
                (image_id, analysis['damage_type'], analysis['hazard_level'],
                 analysis['confidence'], analysis['road_status']),
            )
            print("🔵 [10] Detection result inserted")

            conn.commit()
            print("🔵 [11] Transaction committed")
            img_result = 1
        except Error as e:
            conn.rollback()
            print(f"🔴 [ERROR] Transaction failed: {e}")
            traceback.print_exc()
            img_result = None
        finally:
            cursor.close()
            conn.close()

        print("🔵 [12] About to return response")

        if img_result and img_result > 0:
            return jsonify({
                "status": "success",
                "message": "Report submitted and analyzed",
                "analysis": analysis,
                "location": {"lat": latitude, "lng": longitude}
            }), 201
        else:
            return jsonify({"error": "Failed to store report"}), 400

    except Exception as e:
        print(f"🔴 [FATAL] Unhandled exception: {e}")
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500

@app.route('/api/reports/hazards', methods=['GET'])
def get_hazards():
    """Get all approved hazard reports for the map"""
    try:
        hazards = query_db(
            """
            SELECT dr.detection_id AS id, dr.damage_type, dr.severity AS hazard_level,
                   dr.confidence, dr.road_status, ui.latitude, ui.longitude, dr.detected_at AS created_at
            FROM detection_result dr
            JOIN uploaded_image ui ON dr.image_id = ui.image_id
            WHERE ui.status = 'verified'
            ORDER BY dr.detected_at DESC
            LIMIT 100
            """
        )

        return jsonify({
            "status": "success",
            "hazards": hazards or []
        }), 200
    except Exception as e:
        print(f"Get hazards error: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/reports/user/<int:user_id>', methods=['GET'])
@require_auth
def get_user_reports(user_id):
    """Get reports submitted by a specific user"""
    try:
        reports = query_db(
            """
            SELECT ui.image_id AS id, ui.status, dr.damage_type, dr.severity AS hazard_level,
                   dr.confidence, dr.road_status, ui.latitude, ui.longitude,
                   COALESCE(dr.detected_at, ui.uploaded_at) AS created_at
            FROM uploaded_image ui
            LEFT JOIN detection_result dr ON dr.image_id = ui.image_id
            WHERE ui.user_id = %s
            ORDER BY created_at DESC
            """,
            (user_id,)
        )

        return jsonify({
            "status": "success",
            "reports": reports or []
        }), 200
    except Exception as e:
        print(f"Get user reports error: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/reports/nearby', methods=['GET'])
def get_nearby_hazards():
    """Get hazards near a location (for dashboard)"""
    try:
        lat = float(request.args.get('lat', 19.2456))
        lng = float(request.args.get('lng', 73.1300))
        radius_km = float(request.args.get('radius', 5))

        hazards = query_db(
            """
            SELECT dr.detection_id AS id, dr.damage_type, dr.severity AS hazard_level,
                   dr.confidence, dr.road_status, ui.latitude, ui.longitude, dr.detected_at AS created_at,
                   (6371 * acos(cos(radians(%s)) * cos(radians(ui.latitude)) * cos(radians(ui.longitude) - radians(%s)) + sin(radians(%s)) * sin(radians(ui.latitude)))) AS distance
            FROM detection_result dr
            JOIN uploaded_image ui ON dr.image_id = ui.image_id
            WHERE ui.status = 'verified'
            HAVING distance < %s
            ORDER BY distance ASC
            LIMIT 20
            """,
            (lat, lng, lat, radius_km)
        )

        return jsonify({
            "status": "success",
            "nearby_hazards": hazards or []
        }), 200
    except Exception as e:
        print(f"Get nearby hazards error: {e}")
        return jsonify({"error": str(e)}), 500

# ========== SHELTERS & ROUTE PLANNING ==========

@app.route('/api/shelters', methods=['GET'])
def get_shelters():
    """Get all shelters for rescue guidance"""
    try:
        shelters = query_db(
            "SELECT shelter_id AS id, name, latitude, longitude, capacity, occupancy AS current_occupancy, contact AS phone, status FROM shelter"
        )

        return jsonify({
            "status": "success",
            "shelters": shelters or []
        }), 200
    except Exception as e:
        print(f"Get shelters error: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/shelters/nearest', methods=['GET'])
def get_nearest_shelter():
    """Find nearest safe shelter from a location"""
    try:
        lat = float(request.args.get('lat', 19.2456))
        lng = float(request.args.get('lng', 73.1300))

        shelter = query_db(
            """
            SELECT shelter_id AS id, name, latitude, longitude, capacity,
                   occupancy AS current_occupancy, contact AS phone, status,
                   (6371 * acos(cos(radians(%s)) * cos(radians(latitude)) * cos(radians(longitude) - radians(%s)) + sin(radians(%s)) * sin(radians(latitude)))) AS distance_km
            FROM shelter
            WHERE status = 'available'
            ORDER BY distance_km ASC
            LIMIT 1
            """,
            (lat, lng, lat)
        )

        if shelter:
            return jsonify({
                "status": "success",
                "nearest_shelter": shelter[0]
            }), 200
        else:
            return jsonify({"error": "No shelters found"}), 404
    except Exception as e:
        print(f"Get nearest shelter error: {e}")
        return jsonify({"error": str(e)}), 500

# ========== USER PROFILE / PASSWORD RESET ==========

@app.route('/api/auth/me', methods=['GET'])
@require_auth
def get_me():
    """Profile for the JWT's user. Returns null profile if the row vanished."""
    rows = query_db(
        "SELECT user_id, name, email, phone, role, created_at FROM user WHERE user_id = %s",
        (request.user_id,)
    )
    return jsonify({"profile": rows[0] if rows else None}), 200

@app.route('/api/auth/profile', methods=['PUT'])
@require_auth
def update_profile():
    """Update the signed-in user's name/phone."""
    data = request.json or {}
    name = (data.get('name') or '').strip()
    phone = (data.get('phone') or '').strip()
    if not name:
        return jsonify({"error": "Name cannot be empty"}), 400
    query_db("UPDATE user SET name = %s, phone = %s WHERE user_id = %s",
             (name, phone, request.user_id), fetch=False)
    return get_me()

@app.route('/api/auth/forgot-password', methods=['POST'])
def forgot_password():
    """Local-only password reset: no email service on a fully-local backend,
    so the client sends the new password and the JWT proves the account
    (email → token → POST with new password). Rate-limit note: a real
    deployment should put this behind a captcha or an emailed token."""
    data = request.json or {}
    email = (data.get('email') or '').strip()
    new_password = data.get('new_password') or ''
    if not email or not new_password:
        return jsonify({"error": "Email and new password required"}), 400
    if len(new_password) < 6:
        return jsonify({"error": "Password must be at least 6 characters"}), 400
    rows = query_db("SELECT user_id FROM user WHERE email = %s", (email,))
    if not rows:
        return jsonify({"error": "No account found with that email"}), 404
    password_hash = bcrypt.hashpw(new_password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
    query_db("UPDATE user SET password_hash = %s WHERE user_id = %s",
             (password_hash, rows[0]['user_id']), fetch=False)
    return jsonify({"status": "success", "message": "Password updated"}), 200

# ========== REPORT DETAIL + VERIFICATION ==========

@app.route('/api/reports/manual', methods=['POST'])
@require_auth
def create_manual_report():
    """Debug/testing helper — seed a report without a photo or AI analysis
    (useful when YOLO models aren't installed). Not used by the normal
    report flow."""
    data = request.json or {}
    try:
        lat = float(data['latitude'])
        lng = float(data['longitude'])
    except (KeyError, TypeError, ValueError):
        return jsonify({"error": "latitude and longitude required"}), 400
    damage_type = (data.get('damage_type') or 'unknown').strip()
    hazard_level = (data.get('hazard_level') or 'moderate').strip()
    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(
            "INSERT INTO disaster (type, severity, description, start_time, status) VALUES (%s, %s, 'Manual test report', NOW(), 'active')",
            (damage_type, hazard_level))
        disaster_id = cursor.lastrowid
        cursor.execute(
            "INSERT INTO uploaded_image (user_id, disaster_id, image_url, latitude, longitude, status) VALUES (%s, %s, '', %s, %s, 'verified')",
            (request.user_id, disaster_id, lat, lng))
        image_id = cursor.lastrowid
        cursor.execute(
            "INSERT INTO detection_result (image_id, damage_type, severity, confidence, road_status) VALUES (%s, %s, %s, 1.0, 'Unknown')",
            (image_id, damage_type, hazard_level))
        conn.commit()
        return jsonify({"status": "success", "id": image_id}), 201
    except Error as e:
        conn.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        cursor.close()
        conn.close()

@app.route('/api/reports/<int:image_id>', methods=['GET'])
def get_report_detail(image_id):
    """Full detail for one report — the report-history detail page."""
    rows = query_db(
        """
        SELECT ui.image_id, ui.image_url, ui.description, ui.latitude, ui.longitude,
               ui.status, ui.uploaded_at, ui.user_id,
               dr.damage_type, dr.severity AS hazard_level, dr.confidence, dr.road_status
        FROM uploaded_image ui
        LEFT JOIN detection_result dr ON dr.image_id = ui.image_id
        WHERE ui.image_id = %s
        """,
        (image_id,)
    )
    if not rows:
        return jsonify({"error": "Report not found"}), 404
    r = rows[0]
    if r.get('image_url'):
        r['imageUrl'] = f"/{r['image_url']}"
    return jsonify({"report": r}), 200

@app.route('/api/reports/<int:image_id>/status', methods=['PUT'])
@require_admin
def set_report_status(image_id):
    """Admin verify/reject. Verified reports appear on the public map."""
    data = request.json or {}
    status = data.get('status', '')
    if status not in ('verified', 'rejected', 'pending'):
        return jsonify({"error": "status must be verified|rejected|pending"}), 400
    rows = query_db("UPDATE uploaded_image SET status = %s WHERE image_id = %s",
                    (status, image_id), fetch=False)
    if rows == 0:
        return jsonify({"error": "Report not found"}), 404
    return jsonify({"status": "success", "image_id": image_id, "report_status": status}), 200

@app.route('/api/admin/pending-reports', methods=['GET'])
@require_admin
def admin_pending_reports():
    """Queue for the Admin Dashboard's Reports tab (newest first)."""
    rows = query_db(
        """
        SELECT ui.image_id, ui.image_url, ui.description, ui.latitude, ui.longitude,
               ui.status, ui.uploaded_at, ui.user_id,
               dr.damage_type, dr.severity AS hazard_level, dr.confidence, dr.road_status
        FROM uploaded_image ui
        LEFT JOIN detection_result dr ON dr.image_id = ui.image_id
        WHERE ui.status = 'pending'
        ORDER BY ui.uploaded_at DESC
        LIMIT 100
        """
    )
    for r in rows or []:
        if r.get('image_url'):
            r['imageUrl'] = f"/{r['image_url']}"
    return jsonify({"reports": rows or []}), 200

@app.route('/api/admin/users', methods=['GET'])
@require_admin
def admin_list_users():
    """User list so admins promote by user_id instead of UID-hunting."""
    rows = query_db(
        "SELECT user_id, name, email, phone, role, created_at FROM user ORDER BY created_at DESC LIMIT 200"
    )
    return jsonify({"users": rows or []}), 200

@app.route('/api/admin/promote', methods=['POST'])
@require_admin
def promote_to_admin():
    """Promote by user_id (integer) — replaces the Firebase UID flow."""
    data = request.json or {}
    uid = data.get('uid')
    try:
        uid = int(uid)
    except (TypeError, ValueError):
        return jsonify({"error": "uid must be a numeric user_id"}), 400
    rows = query_db("UPDATE user SET role = 'admin' WHERE user_id = %s", (uid,), fetch=False)
    if rows == 0:
        return jsonify({"error": "User not found"}), 404
    return jsonify({"status": "success", "user_id": uid, "role": "admin"}), 200

# ========== SHELTERS ADMIN CRUD ==========

@app.route('/api/admin/shelters', methods=['POST'])
@require_admin
def admin_create_shelter():
    data = request.json or {}
    name = (data.get('name') or '').strip()
    try:
        lat, lng = float(data.get('latitude')), float(data.get('longitude'))
        capacity, occupancy = int(data.get('capacity') or 0), int(data.get('occupancy') or 0)
    except (TypeError, ValueError):
        return jsonify({"error": "Invalid latitude/longitude/capacity/occupancy"}), 400
    if not name:
        return jsonify({"error": "Name is required"}), 400
    shelter_id = execute_db(
        """INSERT INTO shelter (name, latitude, longitude, capacity, occupancy, contact, status, type)
           VALUES (%s, %s, %s, %s, %s, %s, %s, %s)""",
        (name, lat, lng, capacity, occupancy, data.get('contact') or '',
         data.get('status') or 'available', data.get('type') or 'community'),
    )
    if not shelter_id:
        return jsonify({"error": "Failed to create shelter"}), 500
    return jsonify({"status": "success", "id": shelter_id}), 201

@app.route('/api/admin/shelters/<int:shelter_id>', methods=['PUT', 'DELETE'])
@require_admin
def admin_update_shelter(shelter_id):
    if request.method == 'DELETE':
        query_db("DELETE FROM shelter WHERE shelter_id = %s", (shelter_id,), fetch=False)
        return jsonify({"status": "success"}), 200
    data = request.json or {}
    fields, params = [], []
    for col in ('name', 'latitude', 'longitude', 'capacity', 'occupancy', 'contact', 'status', 'type'):
        if col in data:
            fields.append(f"{col} = %s")
            params.append(data[col])
    if not fields:
        return jsonify({"error": "No fields to update"}), 400
    params.append(shelter_id)
    query_db(f"UPDATE shelter SET {', '.join(fields)} WHERE shelter_id = %s", tuple(params), fetch=False)
    return jsonify({"status": "success"}), 200

# ========== EMERGENCY ALERTS ==========

@app.route('/api/alerts', methods=['GET'])
def get_active_alerts():
    """Active, unexpired alerts for the Emergency Mode page. Also expires
    stale rows lazily so no cron job is needed."""
    query_db("UPDATE emergency_alert SET status='expired' WHERE status='active' AND expires_at < NOW()", fetch=False)
    rows = query_db(
        """SELECT alert_id AS id, disaster_type, severity, affected_area, description,
                  recommended_action, status, created_at, expires_at
           FROM emergency_alert
           WHERE status = 'active'
           ORDER BY created_at DESC LIMIT 50"""
    )
    return jsonify({"alerts": rows or []}), 200

@app.route('/api/admin/alerts', methods=['GET'])
@require_admin
def admin_list_alerts():
    rows = query_db(
        """SELECT alert_id AS id, disaster_type, severity, affected_area, description,
                  recommended_action, status, created_at, expires_at
           FROM emergency_alert ORDER BY created_at DESC LIMIT 50"""
    )
    return jsonify({"alerts": rows or []}), 200

@app.route('/api/admin/alerts', methods=['POST'])
@require_admin
def admin_create_alert():
    data = request.json or {}
    dtype = (data.get('disasterType') or data.get('disaster_type') or '').strip()
    if not dtype:
        return jsonify({"error": "disasterType is required"}), 400
    try:
        hours = float(data.get('validForHours') or 6)
    except (TypeError, ValueError):
        hours = 6.0
    alert_id = execute_db(
        """INSERT INTO emergency_alert
           (disaster_type, severity, affected_area, description, recommended_action, status, created_by, expires_at)
           VALUES (%s, %s, %s, %s, %s, 'active', %s, DATE_ADD(NOW(), INTERVAL %s HOUR))""",
        (dtype, data.get('severity') or 'moderate', data.get('affectedArea') or data.get('affected_area') or '',
         data.get('description') or '', data.get('recommendedAction') or data.get('recommended_action') or '',
         request.user_id, hours),
    )
    if not alert_id:
        return jsonify({"error": "Failed to create alert"}), 500
    return jsonify({"status": "success", "id": alert_id}), 201

@app.route('/api/admin/alerts/<int:alert_id>', methods=['PUT'])
@require_admin
def admin_expire_alert(alert_id):
    """Expire an alert immediately."""
    rows = query_db("UPDATE emergency_alert SET status='expired' WHERE alert_id = %s", (alert_id,), fetch=False)
    if rows == 0:
        return jsonify({"error": "Alert not found"}), 404
    return jsonify({"status": "success"}), 200

# ========== RISK ZONES ==========

@app.route('/api/risk-zones', methods=['GET'])
def get_risk_zones():
    """Public — drawn on the hazard map. boundaries_poly is a JSON array
    of [lat, lng] pairs stored by the admin create endpoint."""
    rows = query_db(
        """SELECT zone_id AS id, boundaries_poly, risk_level, disaster_type, status, updated_at
           FROM zone_risk WHERE status = 'active' ORDER BY updated_at DESC LIMIT 100"""
    )
    zones = []
    for z in rows or []:
        try:
            points = json.loads(z['boundaries_poly'])
        except Exception:
            points = []
        zones.append({
            'id': z['id'],
            'points': points,  # [[lat, lng], ...]
            'riskLevel': z['risk_level'],
            'disasterType': z['disaster_type'],
            'status': z['status'],
        })
    return jsonify({"risk_zones": zones}), 200

@app.route('/api/admin/risk-zones', methods=['POST'])
@require_admin
def admin_create_risk_zone():
    data = request.json or {}
    try:
        center_lat = float(data['centerLat'])
        center_lng = float(data['centerLng'])
        radius_km = float(data['radiusKm'])
    except (KeyError, TypeError, ValueError):
        return jsonify({"error": "centerLat, centerLng, radiusKm are required numbers"}), 400
    d_lat = radius_km / 111.0
    d_lng = radius_km / (111.0 * 0.85)
    points = [
        [round(center_lat - d_lat, 6), round(center_lng - d_lng, 6)],
        [round(center_lat - d_lat, 6), round(center_lng + d_lng, 6)],
        [round(center_lat + d_lat, 6), round(center_lng + d_lng, 6)],
        [round(center_lat + d_lat, 6), round(center_lng - d_lng, 6)],
    ]
    zone_id = execute_db(
        """INSERT INTO zone_risk (boundaries_poly, risk_level, disaster_type, status)
           VALUES (%s, %s, %s, 'active')""",
        (json.dumps(points), data.get('riskLevel') or 'moderate', data.get('disasterType') or ''),
    )
    if not zone_id:
        return jsonify({"error": "Failed to create risk zone"}), 500
    return jsonify({"status": "success", "id": zone_id}), 201

@app.route('/api/admin/risk-zones/<int:zone_id>', methods=['DELETE'])
@require_admin
def admin_delete_risk_zone(zone_id):
    rows = query_db("DELETE FROM zone_risk WHERE zone_id = %s", (zone_id,), fetch=False)
    if rows == 0:
        return jsonify({"error": "Zone not found"}), 404
    return jsonify({"status": "success"}), 200

# ========== EMERGENCY CONTACTS ==========

@app.route('/api/emergency-contacts', methods=['GET', 'POST'])
@require_auth
def emergency_contacts():
    if request.method == 'GET':
        rows = query_db(
            """SELECT contact_id AS id, name, phone, relationship, created_at
               FROM emergency_contact WHERE user_id = %s ORDER BY created_at ASC""",
            (request.user_id,)
        )
        return jsonify({"contacts": rows or []}), 200
    data = request.json or {}
    name = (data.get('name') or '').strip()
    phone = (data.get('phone') or '').strip()
    if not name or not phone:
        return jsonify({"error": "Name and phone are required"}), 400
    contact_id = execute_db(
        "INSERT INTO emergency_contact (user_id, name, phone, relationship) VALUES (%s, %s, %s, %s)",
        (request.user_id, name, phone, (data.get('relationship') or '').strip()),
    )
    if not contact_id:
        return jsonify({"error": "Failed to add contact"}), 500
    return jsonify({"status": "success", "id": contact_id}), 201

@app.route('/api/emergency-contacts/<int:contact_id>', methods=['PUT', 'DELETE'])
@require_auth
def emergency_contact_detail(contact_id):
    owner = query_db("SELECT user_id FROM emergency_contact WHERE contact_id = %s", (contact_id,))
    if not owner or owner[0]['user_id'] != request.user_id:
        return jsonify({"error": "Contact not found"}), 404
    if request.method == 'DELETE':
        query_db("DELETE FROM emergency_contact WHERE contact_id = %s", (contact_id,), fetch=False)
        return jsonify({"status": "success"}), 200
    data = request.json or {}
    query_db(
        "UPDATE emergency_contact SET name = %s, phone = %s, relationship = %s WHERE contact_id = %s",
        ((data.get('name') or '').strip(), (data.get('phone') or '').strip(),
         (data.get('relationship') or '').strip(), contact_id), fetch=False)
    return jsonify({"status": "success"}), 200

# ========== LOCATION SHARING ==========

@app.route('/api/location-shares', methods=['GET', 'POST'])
@require_auth
def location_shares():
    if request.method == 'POST':
        data = request.json or {}
        try:
            hours = float(data.get('durationHours') or 1)
        except (TypeError, ValueError):
            hours = 1.0
        share_id = execute_db(
            """INSERT INTO location_share (user_id, latitude, longitude, expires_at)
               VALUES (%s, %s, %s, DATE_ADD(NOW(), INTERVAL %s HOUR))""",
            (request.user_id, data.get('latitude'), data.get('longitude'), hours),
        )
        if not share_id:
            return jsonify({"error": "Failed to start share"}), 500
        return jsonify({"status": "success", "id": share_id}), 201
    rows = query_db(
        """SELECT share_id AS id, user_id, latitude, longitude, started_at, last_updated, expires_at, active
           FROM location_share WHERE user_id = %s AND active = 1 ORDER BY started_at DESC LIMIT 10""",
        (request.user_id,)
    )
    return jsonify({"shares": rows or []}), 200

@app.route('/api/location-shares/<int:share_id>', methods=['PUT', 'DELETE'])
@require_auth
def location_share_update(share_id):
    """PUT: push a position update or stop early (active:false).
    DELETE: stop sharing."""
    owner = query_db("SELECT user_id FROM location_share WHERE share_id = %s", (share_id,))
    if not owner or owner[0]['user_id'] != request.user_id:
        return jsonify({"error": "Share not found"}), 404
    if request.method == 'DELETE':
        query_db("UPDATE location_share SET active = 0 WHERE share_id = %s", (share_id,), fetch=False)
        return jsonify({"status": "success"}), 200
    data = request.json or {}
    if data.get('active') is False:
        query_db("UPDATE location_share SET active = 0 WHERE share_id = %s", (share_id,), fetch=False)
        return jsonify({"status": "success"}), 200
    query_db(
        """UPDATE location_share SET latitude = %s, longitude = %s, last_updated = NOW() WHERE share_id = %s""",
        (data.get('latitude'), data.get('longitude'), share_id), fetch=False)
    return jsonify({"status": "success"}), 200

# ========== UPLOADS (served locally) ==========

@app.route('/uploads/<path:filename>')
def serve_upload(filename):
    return send_from_directory(UPLOAD_DIR, filename)

# ========== ERROR HANDLER ==========

@app.errorhandler(404)
def not_found(error):
    return jsonify({"error": "Endpoint not found"}), 404

@app.errorhandler(500)
def server_error(error):
    return jsonify({"error": "Internal server error"}), 500

# ========== RUN ==========

if __name__ == '__main__':
    print("=" * 60)
    print("SafeSense Backend Starting...")
    print("=" * 60)
    seed_first_admin()
    print(f"✓ Database: {DB_HOST} / {DB_NAME} (user: {DB_USER}, pass: {'***' if DB_PASSWORD else '(empty)'})")
    print(f"✓ YOLOv8: {'Available' if YOLO_AVAILABLE else 'Not installed (optional)'}")
    print(f"✓ Teachable Machine: {'Available' if TM_AVAILABLE else 'Not installed (optional)'}")
    print(f"✓ JWT Auth: Enabled (token expires in {JWT_EXPIRY_HOURS}h)")
    print("✓ Running on http://0.0.0.0:5000")
    print("=" * 60)
    app.run(debug=True, host='0.0.0.0', port=5000, threaded=True, use_reloader=False)