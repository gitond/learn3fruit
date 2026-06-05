#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage: prep_data_dl.sh "DisplayName1, DisplayName2, ..." COUNT [output_dir]

  DisplayNames   Comma-separated class names (from oidv7-class-descriptions-boxable.csv)
  COUNT          Max images per class
  output_dir     Where to write output files (default: current directory)

Reads from the same directory as this script:
  oidv7-class-descriptions-boxable.csv  (required)
  validation-annotations-bbox.csv       (required; validation split)
  oidv6-train-annotations-bbox.csv      (optional; used to top up if validation is short)

Outputs to output_dir:
  dl<timestamp>.txt          one "split/image_id" per line, ready for downloader.py
  dl<timestamp>matchlog.txt  per-class list of matched image IDs
EOF
    exit 1
}

[[ $# -lt 2 || $# -gt 3 ]] && usage

DISPLAY_NAMES_RAW="$1"
COUNT="$2"
OUTPUT_DIR="${3:-.}"

[[ "$COUNT" =~ ^[1-9][0-9]*$ ]] || { echo "Error: COUNT must be a positive integer" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLASS_CSV="$SCRIPT_DIR/oidv7-class-descriptions-boxable.csv"
VAL_CSV="$SCRIPT_DIR/validation-annotations-bbox.csv"
TRAIN_CSV="$SCRIPT_DIR/oidv6-train-annotations-bbox.csv"

[[ -f "$CLASS_CSV" ]] || { echo "Error: missing $CLASS_CSV" >&2; exit 1; }
[[ -f "$VAL_CSV" ]]   || { echo "Error: missing $VAL_CSV" >&2; exit 1; }

mkdir -p "$OUTPUT_DIR"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_FILE="$OUTPUT_DIR/dl${TIMESTAMP}.txt"
MATCHLOG_FILE="$OUTPUT_DIR/dl${TIMESTAMP}matchlog.txt"

# Temp files cleaned up on exit
TMP_PAIRS="$(mktemp)"
TMP_EXCL="$(mktemp)"
trap 'rm -f "$TMP_PAIRS" "$TMP_EXCL"' EXIT

> "$MATCHLOG_FILE"
first_class=true

IFS=',' read -ra RAW_NAMES <<< "$DISPLAY_NAMES_RAW"

for raw_name in "${RAW_NAMES[@]}"; do
    display_name="$(printf '%s' "$raw_name" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -z "$display_name" ]] && continue

    # --- Resolve label code (case-insensitive match on DisplayName field) ---
    label_code="$(awk -F',' -v name="$display_name" '
        NR > 1 { gsub(/\r$/, "") }
        NR > 1 && tolower($2) == tolower(name) { print $1; exit }
    ' "$CLASS_CSV")"

    if [[ -z "$label_code" ]]; then
        echo "Warning: '$display_name' not found in $CLASS_CSV" >&2
        continue
    fi

    # --- Collect unique ImageIDs from validation split ---
    # Dedup rule: (ImageID, LabelName) counted once — equivalent to unique ImageID
    # since we're already filtering by a single label.
    mapfile -t ids_val < <(awk -F',' -v lbl="$label_code" -v lim="$COUNT" '
        NR > 1 { gsub(/\r$/, "") }
        NR > 1 && $3 == lbl && !seen[$1]++ && ++n <= lim { print $1 }
    ' "$VAL_CSV")

    # --- Supplement from train split if validation didn't reach COUNT ---
    ids_train=()
    need=$(( COUNT - ${#ids_val[@]} ))
    if [[ $need -gt 0 && -f "$TRAIN_CSV" ]]; then
        # Write exclusion list (IDs already collected from validation).
        # Using FILENAME check instead of NR==FNR to handle the empty-file edge case.
        if [[ ${#ids_val[@]} -gt 0 ]]; then
            printf '%s\n' "${ids_val[@]}" > "$TMP_EXCL"
        else
            > "$TMP_EXCL"
        fi
        mapfile -t ids_train < <(
            awk -F',' -v lbl="$label_code" -v lim="$need" -v excf="$TMP_EXCL" '
                FILENAME == excf { excl[$1] = 1; next }
                { gsub(/\r$/, "") }
                $3 == lbl && !excl[$1] && !seen[$1]++ && ++n <= lim { print $1 }
            ' "$TMP_EXCL" "$TRAIN_CSV"
        )
    fi

    # --- Append to matchlog ---
    [[ "$first_class" == "true" ]] || printf '\n' >> "$MATCHLOG_FILE"
    printf '%s\n' "$display_name" >> "$MATCHLOG_FILE"
    [[ ${#ids_val[@]}   -gt 0 ]] && printf '%s\n' "${ids_val[@]}"   >> "$MATCHLOG_FILE"
    [[ ${#ids_train[@]} -gt 0 ]] && printf '%s\n' "${ids_train[@]}" >> "$MATCHLOG_FILE"
    first_class=false

    # --- Accumulate split/id pairs for final deduplication pass ---
    [[ ${#ids_val[@]}   -gt 0 ]] && printf 'validation %s\n' "${ids_val[@]}"   >> "$TMP_PAIRS"
    [[ ${#ids_train[@]} -gt 0 ]] && printf 'train %s\n'      "${ids_train[@]}" >> "$TMP_PAIRS"
done

# Deduplicate across classes: same image matching multiple classes appears once.
# First split seen wins (validation comes before train in TMP_PAIRS).
awk '!seen[$2]++ { print $1 "/" $2 }' "$TMP_PAIRS" | sort > "$OUTPUT_FILE"

echo "Output:    $OUTPUT_FILE ($(wc -l < "$OUTPUT_FILE") unique images)"
echo "Match log: $MATCHLOG_FILE"
