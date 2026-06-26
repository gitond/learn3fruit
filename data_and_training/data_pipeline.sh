#!/usr/bin/env bash
# data_pipeline.sh — Download Open Images V7 samples and produce a Pascal VOC dataset.
#
# USAGE (call from project root):
#   bash data_and_training/data_pipeline.sh "Name1, Name2, ..." COUNT OUTPUT_NAME
#
# INPUTS:
#   DisplayNames  Comma-separated class names as they appear in
#                 oidv7-class-descriptions-boxable.csv (e.g. "Apple, Banana")
#   COUNT         Max images to download per class
#   OUTPUT_NAME   Name of the output directory, created at data_and_training/data/<OUTPUT_NAME>
#
# DEPENDENCIES (must be present in data_and_training/devtools/):
#   prep_data_dl.sh                       — builds the downloader.py image-ID list
#   downloader.py                         — official Open Images downloader (requires boto3, botocore, tqdm)
#   gen_voc_annotations.sh                — generates Pascal VOC XML annotation files
#   oidv7-class-descriptions-boxable.csv  — maps display names to OI label codes
#   validation-annotations-bbox.csv       — bbox annotations (validation split, default)
#
# OUTPUT (data_and_training/data/<OUTPUT_NAME>/):
#   ds/
#     images/
#       <image_id>.jpg ...
#     Annotations/
#       <image_id>.xml ...
#   dl<timestamp>.txt          — image-ID list passed to downloader.py
#   dl<timestamp>matchlog.txt  — per-class report of matched image IDs

set -euo pipefail

# --- Arguments ---
DISPLAY_NAMES="${1:?Usage: $0 \"Name1, Name2, ...\" COUNT OUTPUT_NAME}"
COUNT="${2:?Usage: $0 \"Name1, Name2, ...\" COUNT OUTPUT_NAME}"
OUTPUT_NAME="${3:?Usage: $0 \"Name1, Name2, ...\" COUNT OUTPUT_NAME}"

[[ "$COUNT" =~ ^[1-9][0-9]*$ ]] || { echo "Error: COUNT must be a positive integer" >&2; exit 1; }

# --- Paths (all derived from this script's location; call site doesn't matter) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVTOOLS_DIR="$SCRIPT_DIR/devtools"
OUTPUT_DIR="$SCRIPT_DIR/data/$OUTPUT_NAME"
DS_DIR="$OUTPUT_DIR/ds"

[[ -d "$OUTPUT_DIR" ]] && { echo "Error: $OUTPUT_DIR already exists — choose a different OUTPUT_NAME or remove it first" >&2; exit 1; }
mkdir -p "$DS_DIR/images"

# --- Step 1: Build image-ID list for downloader.py ---
echo "=== [1/3] Building download list ==="
prep_out="$(bash "$DEVTOOLS_DIR/prep_data_dl.sh" "$DISPLAY_NAMES" "$COUNT" "$OUTPUT_DIR")"
echo "$prep_out"

dl_file="$(echo "$prep_out" | awk '/^Output:/ {print $2}')"
[[ -f "$dl_file" ]] || { echo "Error: prep_data_dl.sh did not produce an output file" >&2; exit 1; }

# --- Step 2: Download images ---
echo ""
echo "=== [2/3] Downloading images ==="
python "$DEVTOOLS_DIR/downloader.py" "$dl_file" --download_folder "$DS_DIR/images"

# --- Step 3: Generate Pascal VOC annotation XMLs ---
echo ""
echo "=== [3/3] Generating VOC annotations ==="
bash "$DEVTOOLS_DIR/gen_voc_annotations.sh" "$DS_DIR" "$DISPLAY_NAMES"

# --- Summary ---
n_images="$(find "$DS_DIR/images"      -maxdepth 1 \( -name '*.jpg' -o -name '*.jpeg' \) | wc -l)"
n_annots="$(find "$DS_DIR/Annotations" -maxdepth 1 -name '*.xml' | wc -l)"
echo ""
echo "=== Done ==="
echo "Output:       $OUTPUT_DIR"
echo "ds/images/:   $n_images files"
echo "ds/Annotations/: $n_annots files"
