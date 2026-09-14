# Run from your Backend folder:  python test_predict.py path\to\any_photo.jpg
# This bypasses Flask entirely so we can see the REAL error/crash directly
# in the terminal, instead of it being swallowed as a network reset.
import sys
from pathlib import Path

if len(sys.argv) < 2:
    print("Usage: python test_predict.py <path_to_image.jpg>")
    sys.exit(1)

image_path = sys.argv[1]
if not Path(image_path).exists():
    print(f"File not found: {image_path}")
    sys.exit(1)

print("Importing ultralytics...")
from ultralytics import YOLO
print("✓ Import OK")

MODEL_DIR = Path(__file__).parent / 'ai_model'
model_path = MODEL_DIR / 'flood_best.pt'
print(f"Loading model: {model_path}")
model = YOLO(str(model_path))
print("✓ Model loaded, classes:", model.names)

print(f"Running predict() on {image_path} ...")
results = model.predict(image_path, conf=0.4, verbose=True)
print("✓ Predict finished successfully!")
for r in results:
    print("Boxes found:", len(r.boxes) if r.boxes is not None else 0)
