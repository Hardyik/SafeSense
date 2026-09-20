from flask import Flask, request, jsonify
from flask_cors import CORS
import mysql.connector
from mysql.connector import Error
import os
from pathlib import Path
from dotenv import load_dotenv
from datetime import datetime, timedelta
import tempfile
import traceback
import bcrypt
import jwt
import functools

# Load environment variables — find .env next to this script
dotenv_path = Path(__file__).parent / '.env'
if dotenv_path.exists():
    load_dotenv(dotenv_path=dotenv_path)
    print(f"✓ Loaded .env from {dotenv_path}")
else:
    load_dotenv()
    print(f"⚠ .env not found at {dotenv_path}, using system env vars")

app = Flask(__name__)
CORS(app, resources={r"/api/*": {"origins": "*", "allow_headers": ["Authorization", "Content-Type"], "methods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"]}})

# ========== CONFIGURATION ==========
DB_HOST = os.getenv('DB_HOST', 'localhost')
DB_USER = os.getenv('DB_USER', 'root')
DB_PASSWORD = os.getenv('DB_PASSWORD', '')
DB_NAME = os.getenv('DB_NAME', 'safesense')
JWT_SECRET = os.getenv('JWT_SECRET', os.urandom(32).hex())
JWT_EXPIRY_HOURS = int(os.getenv('JWT_EXPIRY_HOURS', '24'))

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
    print("⚠ YOLOv8 not installed. Install with: pip install ultralytics opencv-python")
except Exception as e:
    YOLO_AVAILABLE = False
    print(f"⚠ YOLO warning: {e}")

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


# ========== YOLO DAMAGE DETECTION ==========
# Map each model's class names -> (hazard_level, road_status)
# ⚠️ EDIT THESE to match the actual class names your models were trained on.
# Run the app once and check the printed "classes = {...}" output at startup
# to see the real names, then fix this dict.
CLASS_INFO = {
    # flood_best.pt
    'flood':              {'hazard_level': 'danger',   'road_status': 'Blocked'},

    # hazard_best.pt — generic "Hazard" class carries no severity info,
    # so default to the cautious end rather than reassuring the user.
    'hazard':             {'hazard_level': 'danger', 'road_status': 'Use extreme caution — hazard type unclear'},

    # hazard_fire_building_best.pt
    'fire':               {'hazard_level': 'danger',   'road_status': 'Blocked'},
    'collapsed_building': {'hazard_level': 'danger',   'road_status': 'Blocked'},
}

def analyze_damage_with_yolo(image_path):
    """
    Run all trained YOLO models on the image, keep the single
    highest-confidence detection across all of them.
    """
    if not YOLO_AVAILABLE:
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

        if best_label is None:
            # No detections above threshold in any model
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
        "yolo_available": YOLO_AVAILABLE
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
            return jsonify({"status": "success", "message": "User registered"}), 201
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
    Upload an image, analyze with YOLOv8, store report in database.
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
        print(f"🔵 [5] YOLO analysis complete: {analysis}")

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
                INSERT INTO uploaded_image (user_id, disaster_id, image_url, latitude, longitude, status)
                VALUES (%s, %s, %s, %s, %s, 'approved')
                """,
                (user_id, disaster_id, image_path, latitude, longitude),
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
    """Get all active hazard reports for the map"""
    try:
        hazards = query_db(
            """
            SELECT dr.detection_id AS id, dr.damage_type, dr.severity AS hazard_level,
                   dr.confidence, dr.road_status, ui.latitude, ui.longitude, dr.detected_at AS created_at
            FROM detection_result dr
            JOIN uploaded_image ui ON dr.image_id = ui.image_id
            WHERE ui.status = 'approved'
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
            SELECT dr.detection_id AS id, dr.damage_type, dr.severity AS hazard_level,
                   dr.confidence, dr.road_status, ui.latitude, ui.longitude, dr.detected_at AS created_at
            FROM detection_result dr
            JOIN uploaded_image ui ON dr.image_id = ui.image_id
            WHERE ui.user_id = %s
            ORDER BY dr.detected_at DESC
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
            WHERE ui.status = 'approved'
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
    print(f"✓ Database: {DB_HOST} / {DB_NAME} (user: {DB_USER}, pass: {'***' if DB_PASSWORD else '(empty)'})")
    print(f"✓ YOLOv8: {'Available' if YOLO_AVAILABLE else 'Not installed (optional)'}")
    print(f"✓ JWT Auth: Enabled (token expires in {JWT_EXPIRY_HOURS}h)")
    print("✓ Running on http://0.0.0.0:5000")
    print("=" * 60)
    app.run(debug=True, host='0.0.0.0', port=5000, threaded=True)