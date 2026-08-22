from flask import Flask, jsonify
from flask_cors import CORS
import mysql.connector
from mysql.connector import Error

app = Flask(__name__)
CORS(app)

# ========== DATABASE CONNECTION ==========
def get_db_connection():
    try:
        connection = mysql.connector.connect(
            host='localhost',
            user='root',
            password='hardik@1310',   # ← Change this
            database='safesense'
        )
        return connection
    except Error as e:
        print(f"Error connecting to MySQL: {e}")
        return None

# ========== ROUTES ==========
@app.route('/')
def home():
    return jsonify({
        "message": "SafeSense Backend is running!",
        "status": "OK"
    })

@app.route('/test-db')
def test_db():
    connection = get_db_connection()
    if connection and connection.is_connected():
        connection.close()
        return jsonify({"message": "Database connected successfully!"})
    else:
        return jsonify({"message": "Failed to connect to database"}), 500

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)