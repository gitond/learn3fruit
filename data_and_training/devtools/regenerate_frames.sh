#!/usr/bin/env bash
set -euo pipefail

INPUT_DIR="${1:?Usage: $0 DIRECTORY}"

if [[ ! -d "$INPUT_DIR" ]]; then
    echo "Error: directory not found: $INPUT_DIR" >&2
    exit 1
fi

command -v ffmpeg >/dev/null 2>&1 || {
    echo "Error: ffmpeg not found" >&2
    exit 1
}

TIMESTAMP_FILE="${INPUT_DIR}/timestamps.csv"

if [[ ! -f "$TIMESTAMP_FILE" ]]; then
    echo "Error: timestamps.csv not found in: $INPUT_DIR" >&2
    exit 1
fi

# Find video files in the directory.
VIDEO_FILES=()

while IFS= read -r -d '' FILE; do
    VIDEO_FILES+=("$FILE")
done < <(
    find "$INPUT_DIR" -maxdepth 1 -type f \
        \( -iname '*.mp4' -o -iname '*.mov' -o -iname '*.mkv' \
           -o -iname '*.avi' -o -iname '*.m4v' -o -iname '*.webm' \) \
        -print0
)

if [[ "${#VIDEO_FILES[@]}" -eq 0 ]]; then
    echo "Error: no video file found in: $INPUT_DIR" >&2
    exit 1
fi

if [[ "${#VIDEO_FILES[@]}" -gt 1 ]]; then
    echo "Error: more than one video file found in: $INPUT_DIR" >&2
    printf '  %s\n' "${VIDEO_FILES[@]}" >&2
    echo "Please leave exactly one source video in the directory." >&2
    exit 1
fi

VIDEO="${VIDEO_FILES[0]}"

echo "Directory:  $INPUT_DIR"
echo "Video:      $(basename "$VIDEO")"
echo "Timestamps: $(basename "$TIMESTAMP_FILE")"
echo

# Remove previously generated frames.
rm -f "$INPUT_DIR"/frame_*.jpg

FRAME_COUNT=0

while IFS=',' read -r FRAME_ID TIMESTAMP_SECONDS _; do

    # Skip the CSV header.
    if [[ "$FRAME_ID" == "frame_id" ]]; then
        continue
    fi

    if [[ -z "$FRAME_ID" || -z "$TIMESTAMP_SECONDS" ]]; then
        echo "Error: invalid row in timestamps.csv:" >&2
        echo "  $FRAME_ID,$TIMESTAMP_SECONDS" >&2
        exit 1
    fi

    OUTPUT_FILE="${INPUT_DIR}/${FRAME_ID}.jpg"

    ffmpeg \
        -hide_banner \
        -loglevel error \
        -i "$VIDEO" \
        -ss "$TIMESTAMP_SECONDS" \
        -frames:v 1 \
        -q:v 2 \
        "$OUTPUT_FILE"

    FRAME_COUNT=$((FRAME_COUNT + 1))

    echo "Generated ${FRAME_ID}.jpg @ ${TIMESTAMP_SECONDS}s"

done < "$TIMESTAMP_FILE"

echo
echo "Done."
echo "Generated $FRAME_COUNT frames in:"
echo "  $INPUT_DIR"
