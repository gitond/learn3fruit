#!/usr/bin/env bash

set -euo pipefail

INPUT_DIR="${1:?Usage: $0 VIDEO_FRAMES_DIRECTORY VIDEO}"
VIDEO="${2:?Usage: $0 VIDEO_FRAMES_DIRECTORY VIDEO}"

if [[ ! -d "$INPUT_DIR" ]]; then
    echo "Error: directory not found: $INPUT_DIR" >&2
    exit 1
fi

command -v ffmpeg >/dev/null 2>&1 || {
    echo "Error: ffmpeg not found" >&2
    exit 1
}

IMAGES_DIR="${INPUT_DIR}/images"
METADATA_DIR="${INPUT_DIR}/metadata"
TIMESTAMP_FILE="${METADATA_DIR}/timestamps.csv"

if [[ ! -f "$TIMESTAMP_FILE" ]]; then
    echo "Error: timestamps.csv not found in: $METADATA_DIR" >&2
    exit 1
fi

if [[ ! -f "$VIDEO" ]]; then
    echo "Error: video not found: $VIDEO" >&2
    exit 1
fi

mkdir -p "$IMAGES_DIR"

echo "Frames directory: $INPUT_DIR"
echo "Video:            $(basename "$VIDEO")"
echo "Timestamps:       $TIMESTAMP_FILE"
echo "Images:            $IMAGES_DIR"
echo

# Remove previously generated frames.
rm -f "$IMAGES_DIR"/uniform_*.jpg
rm -f "$IMAGES_DIR"/hv_*.jpg

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

    OUTPUT_FILE="${IMAGES_DIR}/${FRAME_ID}.jpg"

    ffmpeg \
        -hide_banner \
        -loglevel error \
        -nostdin \
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
echo "  $IMAGES_DIR"
