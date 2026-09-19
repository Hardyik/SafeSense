from flask import Flask, request
from detect import detect_hazard
import os

app = Flask(__name__)

UPLOAD_FOLDER = "uploads"
os.makedirs(UPLOAD_FOLDER, exist_ok=True)


@app.route("/")
def home():
    return "SafeSense Backend is Running!"


@app.route("/detect", methods=["POST"])
def detect():
    if "image" not in request.files:
        return {"error": "No image uploaded"}

    image = request.files["image"]

    image_path = os.path.join(UPLOAD_FOLDER, image.filename)
    image.save(image_path)

    result = detect_hazard(image_path)

    return result


if __name__ == "__main__":
    app.run(debug=True)