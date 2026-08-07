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
#   gen_split.sh                          — stratified train/val split
#   gen_voc_annotations.sh                — generates Pascal VOC XML annotation files
#   oidv7-class-descriptions-boxable.csv  — maps display names to OI label codes
#   validation-annotations-bbox.csv       — bbox annotations (validation split)
#   oidv6-train-annotations-bbox.csv      — bbox annotations (train split, optional; used when val is short)
#
# OUTPUT (data_and_training/data/<OUTPUT_NAME>/):
#   ds/
#     train/
#       images/      <image_id>.jpg ...
#       Annotations/ <image_id>.xml ...
#     val/
#       images/      <image_id>.jpg ...
#       Annotations/ <image_id>.xml ...
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

[[ -d "$OUTPUT_DIR" ]] && {
    echo "Error: $OUTPUT_DIR already exists — choose a different OUTPUT_NAME or remove it first" >&2
    exit 1
}
mkdir -p "$DS_DIR/images"

# --- Step 1: Build image-ID list for downloader.py ---
echo "=== [1/4] Building download list ==="
prep_out="$(bash "$DEVTOOLS_DIR/prep_data_dl.sh" "$DISPLAY_NAMES" "$COUNT" "$OUTPUT_DIR")"
echo "$prep_out"

dl_file="$(echo "$prep_out" | awk '/^Output:/ {print $2}')"
matchlog_file="$(echo "$prep_out" | awk '/^Match log:/ {print $NF}')"
[[ -f "$dl_file" ]]       || { echo "Error: prep_data_dl.sh did not produce an output file" >&2; exit 1; }
[[ -f "$matchlog_file" ]] || { echo "Error: prep_data_dl.sh did not produce a matchlog" >&2; exit 1; }

# --- Step 2: Download images ---
echo ""
echo "=== [2/4] Downloading images ==="
python "$DEVTOOLS_DIR/downloader.py" "$dl_file" --download_folder "$DS_DIR/images"

# --- Step 3: Split into train / val ---
echo ""
echo "=== [3/4] Splitting into train / val ==="
bash "$DEVTOOLS_DIR/gen_split.sh" "$DS_DIR" "$matchlog_file"

# --- Step 4: Generate Pascal VOC annotation XMLs ---
echo ""
echo "=== [4/4] Generating VOC annotations ==="
VAL_CSV="$DEVTOOLS_DIR/validation-annotations-bbox.csv"
TRAIN_CSV="$DEVTOOLS_DIR/oidv6-train-annotations-bbox.csv"
TMP_STDERR="$(mktemp)"
trap 'rm -f "$TMP_STDERR"' EXIT

# Annotate one subdirectory (train/ or val/) against both available CSVs.
# Per-image "no annotations" warnings are suppressed — expected because each CSV
# only covers its own OI split.  Real errors (bad label codes, missing dirs) are
# still forwarded.  A post-check warns only for images with no XML from either CSV.
annotate_subdir() {
    local subdir="$1"
    bash "$DEVTOOLS_DIR/gen_voc_annotations.sh" "$subdir" "$DISPLAY_NAMES" "$VAL_CSV" \
        >/dev/null 2>"$TMP_STDERR"
    grep -v '^Warning: no annotations for' "$TMP_STDERR" >&2 || true

    if [[ -f "$TRAIN_CSV" ]]; then
        bash "$DEVTOOLS_DIR/gen_voc_annotations.sh" "$subdir" "$DISPLAY_NAMES" "$TRAIN_CSV" \
            >/dev/null 2>"$TMP_STDERR"
        grep -v '^Warning: no annotations for' "$TMP_STDERR" >&2 || true
    fi

    local subname
    subname="$(basename "$subdir")"
    for img in "$subdir/images"/*.jpg "$subdir/images"/*.jpeg; do
        [[ -f "$img" ]] || continue
        stem="$(basename "${img%.*}")"
        [[ -f "$subdir/Annotations/${stem}.xml" ]] || \
            echo "Warning: no annotations for $(basename "$img") in $subname/ (not in val or train CSV)" >&2
    done
}

annotate_subdir "$DS_DIR/train"
annotate_subdir "$DS_DIR/val"
rm -f "$TMP_STDERR"

# --- Summary ---
n_train_img="$(find "$DS_DIR/train/images"      -maxdepth 1 \( -name '*.jpg' -o -name '*.jpeg' \) | wc -l)"
n_train_ann="$(find "$DS_DIR/train/Annotations" -maxdepth 1 -name '*.xml' | wc -l)"
n_val_img="$(  find "$DS_DIR/val/images"        -maxdepth 1 \( -name '*.jpg' -o -name '*.jpeg' \) | wc -l)"
n_val_ann="$(  find "$DS_DIR/val/Annotations"   -maxdepth 1 -name '*.xml' | wc -l)"
echo ""
echo "=== Done ==="
echo "Output: $OUTPUT_DIR"
printf "  train/  %4d images  %4d annotations\n" "$n_train_img" "$n_train_ann"
printf "  val/    %4d images  %4d annotations\n" "$n_val_img"   "$n_val_ann"
