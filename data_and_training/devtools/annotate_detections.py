#!/usr/bin/env python3
"""
Interactive JSONL detection annotator.

Usage:
    python annotate_detections.py SOME_FOLDER

Expected structure:
    SOME_FOLDER/
    ├── images/
    │   ├── *.jpg / *.jpeg
    │   └── ...
    └── metadata/
        └── results.jsonl

The program creates:
    SOME_FOLDER/metadata/results_annotated.jsonl

Keyboard:
    T = True Positive
    G = Ghost
    M = Mis-identification
    Left / Right = previous / next detection
    Enter / Space = acknowledge zero-detection frame
    Esc = quit
"""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
from pathlib import Path
import tkinter as tk
from tkinter import messagebox
from PIL import Image, ImageTk


ANNOTATION_VALUES = ("TP", "GHOST", "MIS-ID")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Interactively annotate object-detection results."
    )
    parser.add_argument(
        "folder",
        type=Path,
        help="Root SOME_FOLDER containing images/ and metadata/results.jsonl",
    )
    return parser.parse_args()


def validate_layout(root: Path) -> tuple[Path, Path, Path]:
    if not root.exists():
        raise FileNotFoundError(f"Input folder does not exist: {root}")
    if not root.is_dir():
        raise NotADirectoryError(f"Input path is not a directory: {root}")

    images_dir = root / "images"
    metadata_dir = root / "metadata"
    input_path = metadata_dir / "results.jsonl"

    if not images_dir.is_dir():
        raise FileNotFoundError(f"Missing images directory: {images_dir}")
    if not metadata_dir.is_dir():
        raise FileNotFoundError(f"Missing metadata directory: {metadata_dir}")
    if not input_path.is_file():
        raise FileNotFoundError(f"Missing input JSONL: {input_path}")

    return images_dir, input_path, metadata_dir / "results_annotated.jsonl"


def load_jsonl(path: Path) -> list[dict]:
    records: list[dict] = []

    with path.open("r", encoding="utf-8") as f:
        for line_number, line in enumerate(f, 1):
            if not line.strip():
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError as exc:
                raise ValueError(
                    f"Invalid JSON in {path}, line {line_number}: {exc}"
                ) from exc

            if not isinstance(record, dict):
                raise ValueError(
                    f"{path}, line {line_number}: expected a JSON object."
                )
            if "image" not in record:
                raise ValueError(
                    f"{path}, line {line_number}: missing 'image'."
                )
            if "detections" not in record:
                raise ValueError(
                    f"{path}, line {line_number}: missing 'detections'."
                )
            if not isinstance(record["image"], str):
                raise ValueError(
                    f"{path}, line {line_number}: 'image' must be a string."
                )
            if not record["image"].lower().endswith((".jpg", ".jpeg")):
                raise ValueError(
                    f"{path}, line {line_number}: image must be .jpg or .jpeg: "
                    f"{record['image']!r}"
                )
            if not isinstance(record["detections"], list):
                raise ValueError(
                    f"{path}, line {line_number}: 'detections' must be a list."
                )

            for detection_index, detection in enumerate(record["detections"]):
                if not isinstance(detection, dict):
                    raise ValueError(
                        f"{path}, line {line_number}, detection "
                        f"{detection_index + 1}: expected an object."
                    )

            records.append(record)

    return records


def load_existing_annotations(path: Path, input_records: list[dict]) -> list[dict]:
    """
    Load an existing results_annotated.jsonl only if it is structurally
    compatible with results.jsonl. The original input records are used as
    the authoritative base; only valid per-detection annotations are copied.
    """
    if not path.exists():
        return input_records

    existing = load_jsonl(path)

    if len(existing) != len(input_records):
        raise ValueError(
            f"Existing annotation file has {len(existing)} frames, but input "
            f"has {len(input_records)}. Refusing to merge automatically."
        )

    merged: list[dict] = []

    for frame_index, (original, saved) in enumerate(zip(input_records, existing)):
        if saved.get("image") != original.get("image"):
            raise ValueError(
                f"Existing annotation file does not match input at frame "
                f"{frame_index + 1}: image names differ."
            )

        if len(saved.get("detections", [])) != len(original["detections"]):
            raise ValueError(
                f"Existing annotation file does not match input at frame "
                f"{frame_index + 1}: detection counts differ."
            )

        record = json.loads(json.dumps(original))

        for i, saved_detection in enumerate(saved["detections"]):
            annotation = saved_detection.get("annotation")
            if annotation in ANNOTATION_VALUES:
                record["detections"][i]["annotation"] = annotation

        merged.append(record)

    return merged


def atomic_write_jsonl(path: Path, records: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)

    fd, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        suffix=".tmp",
        dir=path.parent,
        text=True,
    )

    try:
        with open(fd, "w", encoding="utf-8") as f:
            for record in records:
                f.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")))
                f.write("\n")
            f.flush()

        Path(temporary_name).replace(path)
    except Exception:
        try:
            Path(temporary_name).unlink()
        except FileNotFoundError:
            pass
        raise


def annotation_complete(record: dict) -> bool:
    detections = record["detections"]
    return bool(detections) and all(
        d.get("annotation") in ANNOTATION_VALUES for d in detections
    )


def first_unannotated_position(records: list[dict]) -> tuple[int, int] | None:
    for frame_index, record in enumerate(records):
        if not record["detections"]:
            return frame_index, -1

        for detection_index, detection in enumerate(record["detections"]):
            if detection.get("annotation") not in ANNOTATION_VALUES:
                return frame_index, detection_index

    return None


class AnnotatorApp:
    def __init__(
        self,
        root: tk.Tk,
        images_dir: Path,
        output_path: Path,
        records: list[dict],
    ) -> None:
        self.root = root
        self.images_dir = images_dir
        self.output_path = output_path
        self.records = records

        self.frame_index = 0
        self.detection_index = 0
        self.zero_detection_acknowledged = False

        self.current_photo: ImageTk.PhotoImage | None = None
        self.current_image_size: tuple[int, int] | None = None

        self.canvas_width = 1000
        self.canvas_height = 700

        self.root.title("Detection Annotator")
        self.root.geometry("1200x900")
        self.root.minsize(900, 700)

        self._build_ui()
        self.root.bind("<Key>", self._on_key)
        self.root.protocol("WM_DELETE_WINDOW", self._quit)

        position = first_unannotated_position(self.records)
        if position is None:
            self.frame_index = max(0, len(self.records) - 1)
            self.detection_index = max(
                0, len(self.records[self.frame_index]["detections"]) - 1
            )
            self._set_status("All detections are already annotated.")
        else:
            self.frame_index, self.detection_index = position
            if self.detection_index == -1:
                self._print_zero_detection_message()
                self._set_status("Zero detections — press Enter or Space to continue.")

        self._render()

    def _build_ui(self) -> None:
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)

        main = tk.Frame(self.root)
        main.grid(row=0, column=0, sticky="nsew")
        main.columnconfigure(0, weight=1)
        main.rowconfigure(0, weight=1)

        self.canvas = tk.Canvas(
            main,
            width=self.canvas_width,
            height=self.canvas_height,
            background="black",
            highlightthickness=0,
        )
        self.canvas.grid(row=0, column=0, sticky="nsew", padx=10, pady=(10, 5))

        info = tk.Frame(main)
        info.grid(row=1, column=0, sticky="ew", padx=10, pady=5)
        info.columnconfigure(1, weight=1)

        self.frame_label = tk.Label(info, anchor="w", font=("TkDefaultFont", 11))
        self.frame_label.grid(row=0, column=0, columnspan=2, sticky="ew")

        self.detection_label = tk.Label(info, anchor="w", font=("TkDefaultFont", 12, "bold"))
        self.detection_label.grid(row=1, column=0, columnspan=2, sticky="ew", pady=(3, 0))

        self.class_label = tk.Label(info, anchor="w")
        self.class_label.grid(row=2, column=0, sticky="w", pady=(5, 0))

        self.score_label = tk.Label(info, anchor="w")
        self.score_label.grid(row=2, column=1, sticky="w", pady=(5, 0))

        controls = tk.Frame(main)
        controls.grid(row=2, column=0, sticky="ew", padx=10, pady=5)

        tk.Button(
            controls, text="TP (T)", width=15, command=lambda: self._classify("TP")
        ).pack(side="left", padx=(0, 5))
        tk.Button(
            controls, text="GHOST (G)", width=15, command=lambda: self._classify("GHOST")
        ).pack(side="left", padx=5)
        tk.Button(
            controls, text="MIS-ID (M)", width=15, command=lambda: self._classify("MIS-ID")
        ).pack(side="left", padx=5)

        tk.Button(
            controls, text="← Previous", width=12, command=self._previous
        ).pack(side="right", padx=(5, 0))
        tk.Button(
            controls, text="Next →", width=12, command=self._next
        ).pack(side="right", padx=5)

        self.status_label = tk.Label(
            main, anchor="w", justify="left", wraplength=1100
        )
        self.status_label.grid(row=3, column=0, sticky="ew", padx=10, pady=(2, 10))

    def _set_status(self, text: str) -> None:
        self.status_label.config(text=text)

    def _image_path(self, record: dict) -> Path:
        image_name = record["image"]
        # The JSONL filename is expected to be a simple filename, not a path.
        # Reject path traversal / directory components rather than silently
        # interpreting them.
        candidate = Path(image_name)
        if candidate.name != image_name or candidate.is_absolute():
            raise ValueError(
                f"Image reference must be a filename in images/: {image_name!r}"
            )
        if not image_name.lower().endswith((".jpg", ".jpeg")):
            raise ValueError(f"Image is not .jpg/.jpeg: {image_name!r}")

        return self.images_dir / image_name

    def _print_zero_detection_message(self) -> None:
        record = self.records[self.frame_index]
        message = f"Frame {record['image']} has zero detected objects."
        print(message, flush=True)

    def _render(self) -> None:
        self.canvas.delete("all")

        if not self.records:
            self.canvas.create_text(
                self.canvas_width // 2,
                self.canvas_height // 2,
                text="results.jsonl contains no frames.",
                fill="white",
                font=("TkDefaultFont", 18),
            )
            self._set_status("Nothing to annotate.")
            return

        record = self.records[self.frame_index]
        detections = record["detections"]

        try:
            image_path = self._image_path(record)
            image = Image.open(image_path)
            image.load()
        except Exception as exc:
            self.canvas.create_text(
                self.canvas_width // 2,
                self.canvas_height // 2,
                text=f"Could not load image:\n{exc}",
                fill="white",
                font=("TkDefaultFont", 16),
                width=self.canvas_width - 40,
            )
            self._set_status("Image loading error. See the command line for details.")
            return

        original_width, original_height = image.size
        self.current_image_size = (original_width, original_height)

        scale = min(
            self.canvas.winfo_width() / original_width if original_width else 1,
            self.canvas.winfo_height() / original_height if original_height else 1,
        )
        scale = min(scale, 1.0)

        display_width = max(1, int(original_width * scale))
        display_height = max(1, int(original_height * scale))

        display_image = image.resize((display_width, display_height), Image.Resampling.LANCZOS)
        self.current_photo = ImageTk.PhotoImage(display_image)

        offset_x = (self.canvas.winfo_width() - display_width) / 2
        offset_y = (self.canvas.winfo_height() - display_height) / 2

        self.canvas.create_image(
            offset_x,
            offset_y,
            anchor="nw",
            image=self.current_photo,
        )

        self.frame_label.config(
            text=f"Frame {self.frame_index + 1} / {len(self.records)}: {record['image']}"
        )

        if not detections:
            self.detection_label.config(text="No detections")
            self.class_label.config(text="")
            self.score_label.config(text="")
            self._set_status(
                "This frame has zero detected objects. "
                "Press Enter or Space to continue."
            )
            return

        # Clamp in case navigation landed outside the current frame.
        self.detection_index = max(
            0, min(self.detection_index, len(detections) - 1)
        )

        current = detections[self.detection_index]
        annotation = current.get("annotation", "UNANNOTATED")
        self.detection_label.config(
            text=(
                f"Detection {self.detection_index + 1} / {len(detections)}"
                f"    Annotation: {annotation}"
            )
        )
        self.class_label.config(text=f"NN class: {current.get('name', '<missing>')}")
        self.score_label.config(
            text=f"Confidence score: {current.get('score', '<missing>')}"
        )

        for i, detection in enumerate(detections):
            try:
                x = float(detection["x"]) * scale + offset_x
                y = float(detection["y"]) * scale + offset_y
                w = float(detection["w"]) * scale
                h = float(detection["h"]) * scale
            except (KeyError, TypeError, ValueError):
                continue

            is_current = i == self.detection_index
            width = 4 if is_current else 2

            # Tkinter's default outline color is intentionally used for
            # ordinary boxes; the current detection is highlighted by width
            # and a dashed outline.
            kwargs = {
                "width": width,
            }
            if is_current:
                kwargs["dash"] = (8, 4)

            self.canvas.create_rectangle(
                x, y, x + w, y + h, **kwargs
            )

            if is_current:
                label = (
                    f"#{i + 1} {detection.get('name', '<missing>')} "
                    f"{detection.get('score', '')}"
                )
                self.canvas.create_text(
                    x,
                    max(offset_y, y - 4),
                    anchor="sw",
                    text=label,
                    fill="white",
                    font=("TkDefaultFont", 10, "bold"),
                )

        self._set_status(
            "T = TP    G = GHOST    M = MIS-ID    "
            "←/→ = navigate    Esc = quit"
        )

    def _classify(self, annotation: str) -> None:
        record = self.records[self.frame_index]

        if not record["detections"]:
            return

        detection = record["detections"][self.detection_index]
        detection["annotation"] = annotation

        # Persist immediately so an interrupted session loses at most the
        # current keypress, rather than an entire session.
        try:
            atomic_write_jsonl(self.output_path, self.records)
        except Exception as exc:
            messagebox.showerror(
                "Could not save",
                f"Could not save annotations to:\n{self.output_path}\n\n{exc}",
            )
            return

        if self.detection_index + 1 < len(record["detections"]):
            self.detection_index += 1
        else:
            self._advance_to_next_frame()

        self._render()

    def _advance_to_next_frame(self) -> None:
        next_frame = self.frame_index + 1

        while next_frame < len(self.records):
            self.frame_index = next_frame
            self.detection_index = 0

            if self.records[next_frame]["detections"]:
                return

            self._print_zero_detection_message()
            self._render()
            return

        # End of dataset.
        self.frame_index = max(0, len(self.records) - 1)
        if self.records[self.frame_index]["detections"]:
            self.detection_index = len(self.records[self.frame_index]["detections"]) - 1
        else:
            self.detection_index = -1

        self._set_status("All frames have been processed.")

    def _next(self) -> None:
        record = self.records[self.frame_index]

        if not record["detections"]:
            self._advance_to_next_frame()
            self._render()
            return

        if self.detection_index + 1 < len(record["detections"]):
            self.detection_index += 1
        elif self.frame_index + 1 < len(self.records):
            self.frame_index += 1
            self.detection_index = 0
            if not self.records[self.frame_index]["detections"]:
                self._print_zero_detection_message()
        self._render()

    def _previous(self) -> None:
        record = self.records[self.frame_index]

        if record["detections"] and self.detection_index > 0:
            self.detection_index -= 1
            self._render()
            return

        if self.frame_index > 0:
            self.frame_index -= 1
            detections = self.records[self.frame_index]["detections"]
            self.detection_index = max(0, len(detections) - 1)
            self._render()

    def _on_key(self, event: tk.Event) -> None:
        key = event.keysym.lower()

        if key == "escape":
            self._quit()
        elif key == "t":
            self._classify("TP")
        elif key == "g":
            self._classify("GHOST")
        elif key == "m":
            self._classify("MIS-ID")
        elif key in ("return", "space"):
            if not self.records:
                return
            record = self.records[self.frame_index]
            if not record["detections"]:
                self._advance_to_next_frame()
                self._render()
        elif key == "left":
            self._previous()
        elif key == "right":
            self._next()

    def _quit(self) -> None:
        self.root.destroy()


def main() -> int:
    args = parse_args()

    try:
        images_dir, input_path, output_path = validate_layout(args.folder)
        input_records = load_jsonl(input_path)
        records = load_existing_annotations(output_path, input_records)

        # Make sure a partial output is created even before the first keypress.
        # This also gives the user a concrete resumable file.
        atomic_write_jsonl(output_path, records)

        root = tk.Tk()
        AnnotatorApp(root, images_dir, output_path, records)
        root.mainloop()

    except KeyboardInterrupt:
        print("\nInterrupted.", file=sys.stderr)
        return 130
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
