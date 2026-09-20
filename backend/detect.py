from ultralytics import YOLO
import os

# Get the SafeSense main folder
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Model paths
flood_model = YOLO(os.path.join(BASE_DIR, "ai_model", "flood_best.pt"))
hazard_model = YOLO(os.path.join(BASE_DIR, "ai_model", "hazard_best.pt"))
fire_building_model = YOLO(
    os.path.join(BASE_DIR, "ai_model", "hazard_fire_building_best.pt")
)


def detect_hazard(image_path):

    # -------------------------
    # 1. Check Flood
    # -------------------------
    flood_results = flood_model(image_path)

    if len(flood_results[0].boxes) > 0:
        return {
            "hazard": True,
            "type": "Flood",
            "severity": "High"
        }

    # -------------------------
    # 2. Check Hazard model
    # -------------------------
    hazard_results = hazard_model(image_path)

    if len(hazard_results[0].boxes) > 0:
        return {
            "hazard": True,
            "type": "Hazard",
            "severity": "Medium"
        }

    # -------------------------
    # 3. Check Fire / Collapsed Building
    # -------------------------
    fire_building_results = fire_building_model(image_path)

    if len(fire_building_results[0].boxes) > 0:

        # Get the first detected class
        class_id = int(fire_building_results[0].boxes.cls[0])
        detected_type = fire_building_results[0].names[class_id]

        if detected_type == "Fire":
            return {
                "hazard": True,
                "type": "Fire",
                "severity": "High"
            }

        elif detected_type == "Collapsed_Building":
            return {
                "hazard": True,
                "type": "Collapsed Building",
                "severity": "High"
            }

    # -------------------------
    # No hazard detected
    # -------------------------
    return {
        "hazard": False,
        "type": "Safe",
        "severity": "None"
    }