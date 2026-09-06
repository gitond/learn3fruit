#!/usr/bin/env python3

"""
listener.py — inference result stream listener

Reads JSONL inference results from stdin and produces two persistent
representations of the results:

1. A lossless copy of the incoming JSONL stream:
       <PASCAL-VOC-root>/metadata/results.jsonl

   This file is an intermediary between the inference pipeline and
   downstream consumers such as the advanced annotation tools and
   analysis.jq.

2. PASCAL-VOC annotations:
       <PASCAL-VOC-root>/Annotations/<identification-stem>.xml

   For each inference result, the corresponding image is expected at:
       <PASCAL-VOC-root>/images/<image>

   The JSON `image` field becomes the XML `filename`. Each detection
   becomes an XML `object`; `x`, `y`, `x+w`, and `y+h` become
   `xmin`, `ymin`, `xmax`, and `ymax`, respectively. Detection scores
   are not included in the XML output.

Usage:
    ./source.sh | python3 infer.py | python3 listener.py PASCAL-VOC-root

Input:
    One JSON object per line (JSONL) on stdin.

Requirements and behavior:
    - Python standard library only.
    - `Annotations/` and `metadata/` are created if they do not exist.
    - An existing `metadata/results.jsonl` causes the program to abort;
      it is never overwritten or appended to.
    - Existing annotation XML files are never overwritten.
    - `.jpg` and `.jpeg` image extensions are accepted case-insensitively.
    - The referenced image must exist as a regular file in `images/`.
    - Malformed or otherwise invalid input causes a clear error and
      nonzero exit status.
    - The raw input line that causes an error is preserved in
      `metadata/results.jsonl` for debugging.
    - End-of-file on stdin marks the successful end of the input stream.

The JSONL file is intentionally kept in the same format emitted by
`infer.py`; it is not converted into a JSON array.
"""

import argparse
import json
import pathlib
import sys
import xml.etree.ElementTree as ET


def fail(message):
    print(f"listener: error: {message}", file=sys.stderr)
    raise SystemExit(1)


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Read JSONL inference results from stdin, preserve them as "
            "metadata/results.jsonl, and generate PASCAL-VOC annotations."
        )
    )
    parser.add_argument(
        "root",
        type=pathlib.Path,
        help="PASCAL-VOC structure root directory",
    )
    return parser.parse_args()


def validate_record(record, line_number):
    if not isinstance(record, dict):
        fail(f"line {line_number}: JSON value must be an object")

    if "image" not in record:
        fail(f"line {line_number}: missing required field 'image'")
    image = record["image"]
    if not isinstance(image, str) or not image:
        fail(f"line {line_number}: 'image' must be a non-empty string")

    if "/" in image or "\\" in image:
        fail(
            f"line {line_number}: invalid image filename {image!r}; "
            "a filename must not contain path separators"
        )

    suffix = pathlib.Path(image).suffix.lower()
    if suffix not in (".jpg", ".jpeg"):
        fail(
            f"line {line_number}: invalid image filename {image!r}; "
            "only .jpg and .jpeg extensions are allowed"
        )

    if "detections" not in record:
        fail(f"line {line_number}: missing required field 'detections'")
    detections = record["detections"]
    if not isinstance(detections, list):
        fail(f"line {line_number}: 'detections' must be an array")

    for detection_index, detection in enumerate(detections, start=1):
        prefix = f"line {line_number}, detection {detection_index}"
        if not isinstance(detection, dict):
            fail(f"{prefix}: detection must be an object")

        for field in ("name", "score", "x", "y", "w", "h"):
            if field not in detection:
                fail(f"{prefix}: missing required field {field!r}")

        if not isinstance(detection["name"], str):
            fail(f"{prefix}: 'name' must be a string")

        if isinstance(detection["score"], bool) or not isinstance(
            detection["score"], (int, float)
        ):
            fail(f"{prefix}: 'score' must be a number")

        for field in ("x", "y", "w", "h"):
            value = detection[field]
            if isinstance(value, bool) or not isinstance(value, int):
                fail(f"{prefix}: '{field}' must be an integer")


def write_annotation(annotation_path, image, detections):
    root = ET.Element("annotation")

    filename = ET.SubElement(root, "filename")
    filename.text = image

    for detection in detections:
        obj = ET.SubElement(root, "object")

        name = ET.SubElement(obj, "name")
        name.text = detection["name"]

        bndbox = ET.SubElement(obj, "bndbox")

        xmin = ET.SubElement(bndbox, "xmin")
        xmin.text = str(detection["x"])

        ymin = ET.SubElement(bndbox, "ymin")
        ymin.text = str(detection["y"])

        xmax = ET.SubElement(bndbox, "xmax")
        xmax.text = str(detection["x"] + detection["w"])

        ymax = ET.SubElement(bndbox, "ymax")
        ymax.text = str(detection["y"] + detection["h"])

    ET.indent(root, space="  ")
    tree = ET.ElementTree(root)

    try:
        tree.write(
            annotation_path,
            encoding="utf-8",
            xml_declaration=False,
            short_empty_elements=True,
        )
    except OSError as exc:
        fail(f"could not write annotation {annotation_path}: {exc}")


def main():
    args = parse_args()
    root = args.root

    if not root.exists():
        fail(f"PASCAL-VOC root does not exist: {root}")
    if not root.is_dir():
        fail(f"PASCAL-VOC root is not a directory: {root}")

    images_dir = root / "images"
    if not images_dir.exists():
        fail(f"images directory does not exist: {images_dir}")
    if not images_dir.is_dir():
        fail(f"images path is not a directory: {images_dir}")

    annotations_dir = root / "Annotations"
    metadata_dir = root / "metadata"
    results_path = metadata_dir / "results.jsonl"

    try:
        annotations_dir.mkdir(exist_ok=True)
        metadata_dir.mkdir(exist_ok=True)
    except OSError as exc:
        fail(f"could not create required directories: {exc}")

    if results_path.exists():
        fail(
            f"results file already exists: {results_path}; "
            "refusing to overwrite or append to it"
        )

    try:
        results_file = results_path.open("xb")
    except OSError as exc:
        fail(f"could not create results file {results_path}: {exc}")

    # Binary mode preserves the incoming JSONL bytes exactly, including
    # line endings. Each line is decoded as UTF-8 solely for JSON parsing.
    stdin = getattr(sys.stdin, "buffer", sys.stdin)

    try:
        with results_file:
            line_number = 0

            while True:
                raw_line = stdin.readline()
                if not raw_line:
                    break

                line_number += 1

                try:
                    results_file.write(raw_line)
                    results_file.flush()
                except OSError as exc:
                    fail(f"line {line_number}: could not write raw JSONL: {exc}")

                try:
                    text_line = raw_line.decode("utf-8")
                except UnicodeDecodeError as exc:
                    fail(
                        f"line {line_number}: input is not valid UTF-8: {exc}"
                    )

                if not text_line.strip():
                    fail(f"line {line_number}: blank line is not valid JSONL")

                try:
                    record = json.loads(text_line)
                except json.JSONDecodeError as exc:
                    fail(
                        f"line {line_number}: malformed JSON at column "
                        f"{exc.colno}: {exc.msg}"
                    )

                validate_record(record, line_number)

                image = record["image"]
                image_path = images_dir / image

                if not image_path.is_file():
                    fail(
                        f"line {line_number}: image file does not exist "
                        f"or is not a regular file: {image_path}"
                    )

                stem = pathlib.Path(image).stem
                annotation_path = annotations_dir / f"{stem}.xml"

                if annotation_path.exists():
                    fail(
                        f"line {line_number}: annotation already exists: "
                        f"{annotation_path}; refusing to overwrite it"
                    )

                write_annotation(
                    annotation_path,
                    image,
                    record["detections"],
                )

    except BrokenPipeError:
        print("listener: error: input/output pipe was closed", file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
