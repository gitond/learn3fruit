from pathlib import Path

import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision
from PIL import Image, ImageDraw
import json, sys

ROOT = Path(__file__).parent.parent.parent.parent
MODEL_PATH = ROOT / "data_and_training" / "models" / "mediapipe_mobilenet_v2_test" / "model.tflite"
DATA_DIR = ROOT / "data_and_training" / "data" / "smallvoc" / "images"

SCORE_THRESHOLD = 0.1
USE_DATA_DISPLAY = True  # True: pipe JSON to data_display.py  |  False: PIL display inline

def find_test_image() -> Path:
    matches = list(DATA_DIR.glob("voctest.*"))
    if not matches:
        raise FileNotFoundError(f"No voctest.* found in {DATA_DIR}")
    return matches[0]


def main() -> None:
    test_image_path = find_test_image()

    base_options = python.BaseOptions(model_asset_path=str(MODEL_PATH))
    options = vision.ObjectDetectorOptions(
        base_options=base_options,
        score_threshold=SCORE_THRESHOLD,
    )
    detector = vision.ObjectDetector.create_from_options(options)

    mp_image = mp.Image.create_from_file(str(test_image_path))
    result = detector.detect(mp_image)

    if USE_DATA_DISPLAY:
        # PIPING TO data_display.py
        print(json.dumps([
            {"name":  det.categories[0].category_name,
             "score": det.categories[0].score,
             "x": det.bounding_box.origin_x, "y": det.bounding_box.origin_y,
             "w": det.bounding_box.width,     "h": det.bounding_box.height}
            for det in result.detections
        ]))
    else:
        # DETECTION PRINTS
        print(f"Test image: {test_image_path}")

        print(f"Detected {len(result.detections)} object(s):")
        for i, detection in enumerate(result.detections):
            bbox = detection.bounding_box
            cat = detection.categories[0]
            print(
                f"  [{i}] {cat.category_name} ({cat.score:.2f})"
                f" — box: x={bbox.origin_x} y={bbox.origin_y}"
                f" w={bbox.width} h={bbox.height}"
            )

        # DISPLAYING ANNOTATIONS THROUGH BUILT IN PIL METHOD
        img = Image.open(test_image_path)
        draw = ImageDraw.Draw(img)
        for detection in result.detections:
            bbox = detection.bounding_box
            cat = detection.categories[0]
            x0, y0 = bbox.origin_x, bbox.origin_y
            x1, y1 = x0 + bbox.width, y0 + bbox.height
            draw.rectangle([x0, y0, x1, y1], outline="red", width=3)
            draw.text((x0, max(0, y0 - 15)), f"{cat.category_name} {cat.score:.2f}", fill="red")
        img.show()


if __name__ == "__main__":
    main()
