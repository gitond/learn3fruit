#!/usr/bin/env python3
"""
data_display.py — display a single image with bounding-box annotations or
                  detection results overlaid as colour-coded rectangles.

═══════════════════════════════════════════════════════════════════════════════
USAGE
═══════════════════════════════════════════════════════════════════════════════

Annotation mode  (stdin is a terminal — reads Pascal VOC XML):
    python data_and_training/data_display.py DS_DIR IMAGE_STEM

Detection mode  (stdin carries data — reads JSON from stdin, ignores XML):
    python my_inference.py | python data_and_training/data_display.py DS_DIR IMAGE_STEM

ARGUMENTS
    DS_DIR        Root of a Pascal VOC dataset.  Must contain:
                      images/       — JPEG images (.jpg or .jpeg)
                      Annotations/  — VOC XML files  (annotation mode only)
    IMAGE_STEM    Filename without extension (e.g. "0035a4bfeda1b637").
                  Loaded from DS_DIR/images/<IMAGE_STEM>.jpg,
                  falling back to .jpeg if .jpg is not present.

═══════════════════════════════════════════════════════════════════════════════
STDIN FORMAT  (detection mode)
═══════════════════════════════════════════════════════════════════════════════

A single JSON array written to stdout by the inference script:

    [
      {"name": "apple",  "score": 0.91, "x": 100, "y": 50, "w": 200, "h": 150},
      {"name": "banana", "score": 0.85, "x": 300, "y": 100, "w": 80,  "h": 120}
    ]

Fields:
    name   str    Class label.
    x, y   int    Top-left corner in pixels.
                  Matches MediaPipe BoundingBox fields origin_x / origin_y.
    w, h   int    Width and height in pixels.
                  Matches MediaPipe BoundingBox fields width / height.
    score  float  Confidence score [0, 1].  Key is optional — omit if unavailable.

Minimal wrapper to pipe from mediapipe_obd_infer.py:
    import json, sys
    # after: result = detector.detect(mp_image)
    print(json.dumps([
        {"name":  det.categories[0].category_name,
         "score": det.categories[0].score,
         "x": det.bounding_box.origin_x, "y": det.bounding_box.origin_y,
         "w": det.bounding_box.width,     "h": det.bounding_box.height}
        for det in result.detections
    ]))

═══════════════════════════════════════════════════════════════════════════════
OUTPUT
═══════════════════════════════════════════════════════════════════════════════

stdout  Per-class object count, printed before the window opens:
            apple : 2
            banana: 1

window  matplotlib figure — image with colour-coded bounding boxes.
        One colour per class, consistent within a call.
        Box labels: "<class>" in annotation mode, "<class> <score>" in detection mode.

═══════════════════════════════════════════════════════════════════════════════
DEPENDENCIES
═══════════════════════════════════════════════════════════════════════════════

stdlib      : argparse, json, pathlib, sys, tempfile, xml.etree.ElementTree
third-party : matplotlib >= 3.7  (tested with 3.10.9), Pillow (PIL.Image.show for display)
"""

import argparse
import json
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

import matplotlib.patches as mpatches
import matplotlib.pyplot as plt
from PIL import Image

# Tab10 palette — 10 perceptually distinct colours for categorical classes.
_PALETTE: tuple = plt.matplotlib.colormaps["tab10"].colors


def _color(name: str, index: dict[str, int]) -> tuple:
    if name not in index:
        index[name] = len(index) % len(_PALETTE)
    return _PALETTE[index[name]]


def _find_image(ds_dir: Path, stem: str) -> Path:
    for ext in (".jpg", ".jpeg"):
        p = ds_dir / "images" / (stem + ext)
        if p.exists():
            return p
    raise FileNotFoundError(f"No .jpg/.jpeg found for '{stem}' in {ds_dir / 'images'}")


def _load_voc(ds_dir: Path, stem: str) -> list[dict]:
    xml_path = ds_dir / "Annotations" / (stem + ".xml")
    if not xml_path.exists():
        raise FileNotFoundError(f"Annotation file not found: {xml_path}")
    root = ET.parse(xml_path).getroot()
    boxes = []
    for obj in root.findall("object"):
        bb = obj.find("bndbox")
        boxes.append({
            "name": obj.findtext("name", "").strip(),
            "xmin": int(bb.findtext("xmin")),
            "ymin": int(bb.findtext("ymin")),
            "xmax": int(bb.findtext("xmax")),
            "ymax": int(bb.findtext("ymax")),
        })
    return boxes


def _load_detections() -> list[dict]:
    boxes = []
    for d in json.load(sys.stdin):
        boxes.append({
            "name":  d["name"],
            "xmin":  int(d["x"]),
            "ymin":  int(d["y"]),
            "xmax":  int(d["x"]) + int(d["w"]),
            "ymax":  int(d["y"]) + int(d["h"]),
            "score": d.get("score"),
        })
    return boxes


def _print_counts(boxes: list[dict], mode: str) -> None:
    counts: dict[str, int] = {}
    for b in boxes:
        counts[b["name"]] = counts.get(b["name"], 0) + 1
    width = max(len(n) for n in counts) if counts else 0
    print(f"Per-class {mode} ({sum(counts.values())} total):")
    for name in sorted(counts):
        print(f"  {name:<{width}}: {counts[name]}")


def _show(image_path: Path, boxes: list[dict], title: str) -> None:
    img = plt.imread(str(image_path))
    fig, ax = plt.subplots(figsize=(10, 8))
    ax.imshow(img)
    ax.set_axis_off()
    fig.suptitle(title, fontsize=10)

    color_index: dict[str, int] = {}
    legend: dict[str, mpatches.Patch] = {}

    for box in boxes:
        name = box["name"]
        color = _color(name, color_index)
        xmin, ymin = box["xmin"], box["ymin"]
        w, h = box["xmax"] - xmin, box["ymax"] - ymin

        ax.add_patch(mpatches.Rectangle(
            (xmin, ymin), w, h,
            linewidth=2, edgecolor=color, facecolor="none",
        ))

        label = f"{name} {box['score']:.2f}" if box.get("score") is not None else name
        ax.text(
            xmin, max(0, ymin - 4), label,
            color="white", fontsize=8, fontweight="bold",
            bbox=dict(facecolor=color, alpha=0.85, pad=1, edgecolor="none"),
        )

        if name not in legend:
            legend[name] = mpatches.Patch(color=color, label=name)

    if legend:
        ax.legend(handles=list(legend.values()), loc="upper right", fontsize=8)

    plt.tight_layout()

    # Agg backend (default on headless systems) cannot open a window via plt.show().
    # Render to a temp file and delegate display to PIL, matching mediapipe_obd_infer.py.
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        fig.savefig(tmp.name, bbox_inches="tight", dpi=150)
        tmp_path = tmp.name
    plt.close(fig)
    Image.open(tmp_path).show()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Display a VOC-annotated image or piped detection results.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("ds_dir",     metavar="DS_DIR",      type=Path)
    parser.add_argument("image_stem", metavar="IMAGE_STEM")
    args = parser.parse_args()

    image_path = _find_image(args.ds_dir, args.image_stem)

    if sys.stdin.isatty():
        boxes = _load_voc(args.ds_dir, args.image_stem)
        mode = "annotations"
    else:
        boxes = _load_detections()
        mode = "detections"

    _print_counts(boxes, mode)
    _show(image_path, boxes, title=f"{args.image_stem} — {mode}")


if __name__ == "__main__":
    main()
