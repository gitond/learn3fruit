#!/usr/bin/env python3
import argparse
import json
from datetime import datetime
from pathlib import Path
from typing import Any

from mediapipe_model_maker import object_detector

ROOT = Path(__file__).parent.parent
DATA_DIR = ROOT / "data_and_training" / "data"
MODELS_DIR = ROOT / "data_and_training" / "models"
HPARAMS_FILE = ROOT / "data_and_training" / "devtools" / "hyperparameters.json"


def load_profile(profile: str) -> dict[str, Any]:
    with open(HPARAMS_FILE) as f:
        profiles = json.load(f)
    if profile not in profiles:
        available = ", ".join(profiles.keys())
        raise ValueError(f"Unknown profile '{profile}'. Available: {available}")
    return profiles[profile]


def main() -> None:
    parser = argparse.ArgumentParser(description="Train SSD + MobileNet-v2 on the learn3fruit dataset.")
    parser.add_argument("--hyperparameters", required=True,
                        help="Profile from hyperparameters.json (e.g. 1660super, dual3090)")
    parser.add_argument("--dataset", default="l3fds",
                        help="Dataset name under data_and_training/data/ (default: l3fds)")
    args = parser.parse_args()

    hp = load_profile(args.hyperparameters)

    ds_dir = DATA_DIR / args.dataset / "ds"
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    run_dir = MODELS_DIR / f"ssd_plus_mobilenet_v2_l3f_{timestamp}"
    model_out = run_dir / "model.tflite"
    run_dir.mkdir(parents=True, exist_ok=True)

    print(f"Dataset:  {ds_dir}")
    print(f"Run dir:  {run_dir}")
    print(f"Profile:  {args.hyperparameters} — {hp}")

    train_data = object_detector.Dataset.from_pascal_voc_folder(str(ds_dir / "train"))
    val_data = object_detector.Dataset.from_pascal_voc_folder(str(ds_dir / "val"))

    epochs = hp["epochs"]
    hparams = object_detector.HParams(
        learning_rate=hp["learning_rate"],
        batch_size=hp["batch_size"],
        epochs=epochs,
        cosine_decay_epochs=hp.get("cosine_decay_epochs") or epochs,
        cosine_decay_alpha=hp["cosine_decay_alpha"],
        num_gpus=hp["num_gpus"],
        distribution_strategy=hp["distribution_strategy"],
        export_dir=str(run_dir / "checkpoints"),
    )
    options = object_detector.ObjectDetectorOptions(
        supported_model=object_detector.SupportedModels.MOBILENET_V2,
        hparams=hparams,
    )

    model = object_detector.ObjectDetector.create(train_data, val_data, options)
    model.export_model(str(model_out))
    print(f"Exported: {model_out}")


if __name__ == "__main__":
    main()
