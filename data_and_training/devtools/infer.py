from pathlib import Path

import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision
from PIL import Image, ImageDraw
import json
import sys

ROOT = Path(__file__).parent.parent.parent
CURRENT_MODEL = "ssd_plus_mobilenet_v2_l3f_20260807_225848"
MODEL_PATH = ROOT / "data_and_training" / "models" / CURRENT_MODEL / "model.tflite"

SCORE_THRESHOLD = 0.1
USE_DATA_DISPLAY = True  # True: pipe JSON to data_display.py  |  False: PIL display inline


def find_input_path() -> Path:
    if len(sys.argv) != 2:
        raise SystemExit(
            "Usage: python infer.py IMAGE_PATH_OR_DIRECTORY"
        )

    path = Path(sys.argv[1])

    if not path.exists():
        raise FileNotFoundError(path)

    if not path.is_file() and not path.is_dir():
        raise ValueError(f"Input path is neither a file nor a directory: {path}")

    return path


def find_images(directory: Path) -> list[Path]:
    """Return supported images in deterministic filename order."""
    images = sorted(
        (
            path
            for path in directory.iterdir()
            if path.is_file() and path.suffix.lower() in {".jpg", ".jpeg"}
        ),
        key=lambda path: path.name.lower(),
    )

    if not images:
        raise FileNotFoundError(
            f"No .jpg or .jpeg images found in directory: {directory}"
        )

    return images


def run_inference(
    detector: vision.ObjectDetector,
    image_path: Path,
) -> list[dict]:
    """Run inference on one image and return serializable detections."""
    mp_image = mp.Image.create_from_file(str(image_path))
    result = detector.detect(mp_image)

    return [
        {
            "name": det.categories[0].category_name,
            "score": det.categories[0].score,
            "x": det.bounding_box.origin_x,
            "y": det.bounding_box.origin_y,
            "w": det.bounding_box.width,
            "h": det.bounding_box.height,
        }
        for det in result.detections
    ]


def output_json(image_path: Path, detections: list[dict]) -> None:
    """
    Output one JSON object for one image.

    One image:
        {"image": "image.jpg", "detections": [...]}

    When processing a directory, one such object is written per line,
    allowing the output to be consumed as a JSON Lines stream.
    """
    print(json.dumps({
        "image": image_path.name,
        "detections": detections,
    }))


def display_results(image_path: Path, detections: list[dict]) -> None:
    """Display detections inline using the existing PIL implementation."""
    print(f"Test image: {image_path}")

    print(f"Detected {len(detections)} object(s):")
    for i, detection in enumerate(detections):
        print(
            f"  [{i}] {detection['name']} ({detection['score']:.2f})"
            f" — box: x={detection['x']} y={detection['y']}"
            f" w={detection['w']} h={detection['h']}"
        )

    img = Image.open(image_path)
    draw = ImageDraw.Draw(img)

    for detection in detections:
        x0 = detection["x"]
        y0 = detection["y"]
        x1 = x0 + detection["w"]
        y1 = y0 + detection["h"]

        draw.rectangle(
            [x0, y0, x1, y1],
            outline="red",
            width=3,
        )
        draw.text(
            (x0, max(0, y0 - 15)),
            f"{detection['name']} {detection['score']:.2f}",
            fill="red",
        )

    img.show()


def main() -> None:
    input_path = find_input_path()

    base_options = python.BaseOptions(model_asset_path=str(MODEL_PATH))
    options = vision.ObjectDetectorOptions(
        base_options=base_options,
        score_threshold=SCORE_THRESHOLD,
    )
    detector = vision.ObjectDetector.create_from_options(options)

    if input_path.is_file():
        image_paths = [input_path]
    else:
        image_paths = find_images(input_path)

    for image_path in image_paths:
        detections = run_inference(detector, image_path)

        if USE_DATA_DISPLAY:
            output_json(image_path, detections)
        else:
            # The inline PIL display mode is primarily intended for
            # single-image use. Directory input will display each image
            # sequentially.
            display_results(image_path, detections)


if __name__ == "__main__":
    main()
