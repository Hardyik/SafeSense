# Run this ONCE from your Backend/ai_model folder:
#   python fix_keras_model.py
#
# Teachable Machine exports .h5 files in the old Keras 2 (tf.keras) format,
# which includes a 'groups': 1 parameter on DepthwiseConv2D layers. Modern
# Keras 3 (bundled with recent tensorflow) no longer accepts that parameter,
# causing "Unrecognized keyword arguments passed to DepthwiseConv2D" on load.
# This strips the harmless leftover parameter directly from the file so it
# loads normally afterward. Safe to run — it doesn't change model behavior,
# just removes a deprecated config field.

import h5py
import shutil
from pathlib import Path

MODEL_PATH = Path(__file__).parent / "keras_model.h5"
BACKUP_PATH = Path(__file__).parent / "keras_model_ORIGINAL_BACKUP.h5"

if not MODEL_PATH.exists():
    print(f"❌ Could not find {MODEL_PATH}")
    exit(1)

# Keep a backup just in case, before touching anything
if not BACKUP_PATH.exists():
    shutil.copy(MODEL_PATH, BACKUP_PATH)
    print(f"✓ Backup saved to {BACKUP_PATH}")

with h5py.File(MODEL_PATH, mode="r+") as f:
    model_config_string = f.attrs.get("model_config")
    if model_config_string is None:
        print("❌ No model_config attribute found — this file may not be a standard Keras h5 export.")
        exit(1)

    if isinstance(model_config_string, bytes):
        model_config_string = model_config_string.decode("utf-8")

    if '"groups": 1,' in model_config_string:
        model_config_string = model_config_string.replace('"groups": 1,', '')
        f.attrs.modify("model_config", model_config_string)
        f.flush()
        # Verify it actually took
        check = f.attrs.get("model_config")
        if isinstance(check, bytes):
            check = check.decode("utf-8")
        assert '"groups": 1,' not in check
        print("✓ Patched successfully — 'groups': 1 removed from model_config")
    else:
        print("ℹ No 'groups': 1 found — file may already be patched, or use a different format.")

print("\nDone. Try running your Flask app again.")
