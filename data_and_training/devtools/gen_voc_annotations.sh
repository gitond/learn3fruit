#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage: gen_voc_annotations.sh ROOT_DIR "DisplayName1, DisplayName2, ..." [annotation_csv]

  ROOT_DIR        Directory with an images/ subdirectory containing .jpg/.jpeg files
  DisplayNames    Comma-separated class names (from oidv7-class-descriptions-boxable.csv)
  annotation_csv  Bbox CSV to query (default: validation-annotations-bbox.csv in script dir)

Creates ROOT_DIR/Annotations/<id>.xml for every image in ROOT_DIR/images/.
Images with no matching annotations are skipped with a warning.
EOF
    exit 1
}

[[ $# -lt 2 || $# -gt 3 ]] && usage

ROOT_DIR="${1%/}"
DISPLAY_NAMES_RAW="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLASS_CSV="$SCRIPT_DIR/oidv7-class-descriptions-boxable.csv"
ANN_CSV="${3:-$SCRIPT_DIR/validation-annotations-bbox.csv}"

[[ -d "$ROOT_DIR/images" ]] || { echo "Error: $ROOT_DIR/images not found" >&2; exit 1; }
[[ -f "$CLASS_CSV" ]]       || { echo "Error: missing $CLASS_CSV" >&2; exit 1; }
[[ -f "$ANN_CSV" ]]         || { echo "Error: missing $ANN_CSV" >&2; exit 1; }

IMAGES_DIR="$ROOT_DIR/images"
ANNOT_DIR="$ROOT_DIR/Annotations"
mkdir -p "$ANNOT_DIR"

# --- Resolve display names to label codes ---
IFS=',' read -ra RAW_NAMES <<< "$DISPLAY_NAMES_RAW"
declare -A CODE_TO_NAME  # label_code -> lowercase display_name

for raw_name in "${RAW_NAMES[@]}"; do
    display_name="$(printf '%s' "$raw_name" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -z "$display_name" ]] && continue

    label_code="$(awk -F',' -v name="$display_name" '
        NR > 1 { gsub(/\r$/, "") }
        NR > 1 && tolower($2) == tolower(name) { print $1; exit }
    ' "$CLASS_CSV")"

    if [[ -z "$label_code" ]]; then
        echo "Warning: '$display_name' not found in $CLASS_CSV" >&2
        continue
    fi

    CODE_TO_NAME["$label_code"]="$(printf '%s' "$display_name" | tr '[:upper:]' '[:lower:]')"
done

[[ ${#CODE_TO_NAME[@]} -eq 0 ]] && { echo "Error: no valid label codes resolved" >&2; exit 1; }

# --- Collect image IDs from images/ ---
declare -A IMAGE_FILES  # image_id -> filename (e.g. abc123.jpg)
for img in "$IMAGES_DIR"/*.jpg "$IMAGES_DIR"/*.jpeg; do
    [[ -f "$img" ]] || continue
    fname="$(basename "$img")"
    IMAGE_FILES["${fname%.*}"]="$fname"
done

[[ ${#IMAGE_FILES[@]} -eq 0 ]] && { echo "Error: no .jpg/.jpeg files in $IMAGES_DIR" >&2; exit 1; }

# --- Build awk mapping string for label code -> display name ---
# Label codes are /m/xxxxx (no colons or pipes); our lowercased class names
# (apple, orange (fruit), banana, knife, bowl, spoon) also have neither.
mapping=""
for code in "${!CODE_TO_NAME[@]}"; do
    mapping+="${code}:${CODE_TO_NAME[$code]}|"
done
mapping="${mapping%|}"

# --- Filter annotation CSV in a single pass ---
# Output format per matching row: image_id display_name XMin XMax YMin YMax
# (coordinates stay normalized here; denormalization happens per-image below)
TMP_FILTERED="$(mktemp)"
trap 'rm -f "$TMP_FILTERED"' EXIT

awk -F',' \
    -v ids="${!IMAGE_FILES[*]}" \
    -v codes="${!CODE_TO_NAME[*]}" \
    -v mapping="$mapping" '
    BEGIN {
        n = split(ids, a, " ")
        for (i = 1; i <= n; i++) id_set[a[i]] = 1
        m = split(codes, b, " ")
        for (i = 1; i <= m; i++) code_set[b[i]] = 1
        k = split(mapping, c, "|")
        for (i = 1; i <= k; i++) {
            sep = index(c[i], ":")
            code_name[substr(c[i], 1, sep-1)] = substr(c[i], sep+1)
        }
    }
    NR > 1 {
        gsub(/\r$/, "")
        if (id_set[$1] && code_set[$3])
            print $1, code_name[$3], $5, $6, $7, $8
    }
' "$ANN_CSV" > "$TMP_FILTERED"

# --- Generate one XML per image ---
generated=0
skipped=0

for image_id in "${!IMAGE_FILES[@]}"; do
    filename="${IMAGE_FILES[$image_id]}"
    img_path="$IMAGES_DIR/$filename"
    xml_path="$ANNOT_DIR/${image_id}.xml"

    # Extract image dimensions from `file` output.
    # The standalone "WxH" token (e.g. "1024x1024") is distinct from
    # "density 1x1" which includes the word "density" and doesn't match ^[0-9]+x[0-9]+$.
    dims="$(file "$img_path" | awk -F', ' '{
        for (i = 1; i <= NF; i++)
            if ($i ~ /^[0-9]+x[0-9]+$/) { print $i; exit }
    }')"
    if [[ -z "$dims" ]]; then
        echo "Warning: could not read dimensions of $filename, skipping" >&2
        (( ++skipped ))
        continue
    fi
    width="${dims%x*}"
    height="${dims#*x}"

    # Build <object> blocks for this image, denormalizing bbox coordinates.
    # TMP_FILTERED columns: image_id display_name XMin XMax YMin YMax
    xml_objects="$(awk -v id="$image_id" -v w="$width" -v h="$height" '
        $1 == id {
            printf "  <object>\n    <name>%s</name>\n    <bndbox>\n      <xmin>%d</xmin>\n      <ymin>%d</ymin>\n      <xmax>%d</xmax>\n      <ymax>%d</ymax>\n    </bndbox>\n  </object>\n",
                $2,
                int($3*w + 0.5), int($5*h + 0.5),
                int($4*w + 0.5), int($6*h + 0.5)
        }
    ' "$TMP_FILTERED")"

    if [[ -z "$xml_objects" ]]; then
        echo "Warning: no annotations for $filename, skipping" >&2
        (( ++skipped ))
        continue
    fi

    {
        printf '<annotation>\n'
        printf '  <filename>%s</filename>\n' "$filename"
        printf '%s' "$xml_objects"
        printf '</annotation>\n'
    } > "$xml_path"

    (( ++generated ))
done

echo "Generated $generated XML files in $ANNOT_DIR"
[[ $skipped -gt 0 ]] && echo "Skipped   $skipped images (no matching annotations)"
