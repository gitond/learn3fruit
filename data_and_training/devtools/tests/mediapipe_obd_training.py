from pathlib import Path

from mediapipe_model_maker import object_detector

ROOT = Path(__file__).parent.parent.parent.parent
DUMMY_DATA = ROOT / "data_and_training" / "data" / "2-image-voc"
MODEL_OUT = ROOT / "data_and_training" / "models" / "mediapipe_mobilenet_v2_test" / "model.tflite"


def main() -> None:
    MODEL_OUT.parent.mkdir(parents=True, exist_ok=True)

    train_data = object_detector.Dataset.from_pascal_voc_folder(str(DUMMY_DATA))
    val_data = object_detector.Dataset.from_pascal_voc_folder(str(DUMMY_DATA))

    options = object_detector.ObjectDetectorOptions(
        supported_model=object_detector.SupportedModels.MOBILENET_V2,
        hparams=object_detector.HParams(epochs=1, batch_size=2),
    )
    model = object_detector.ObjectDetector.create(train_data, val_data, options)
    model.export_model(str(MODEL_OUT))
    print(f"Exported: {MODEL_OUT}")


if __name__ == "__main__":
    main()
