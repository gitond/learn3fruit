#!/usr/bin/env bash

set -euo pipefail

# Generate uniformly distributed JPEG frames from a video.
#
# Usage:
#   ./data_and_training/devtools/sample_video.sh VIDEO [NUMBER_OF_FRAMES]
#
# Example:
#   ./data_and_training/devtools/sample_video.sh \
#       data_and_training/data/myvideotest/sample.mp4
#
# Default number of frames: 130
#
# Output is placed next to the input video:
#   <video>_frames/
#       frame_0001.jpg
#       frame_0002.jpg
#       ...
#       frame_0130.jpg
#       timestamps.csv

INPUT="${1:?Usage: $0 VIDEO [NUMBER_OF_FRAMES]}"
NUM_FRAMES="${2:-130}"

if [[ ! -f "$INPUT" ]]; then
    echo "Error: video not found: $INPUT" >&2
    exit 1
fi

if ! [[ "$NUM_FRAMES" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: NUMBER_OF_FRAMES must be a positive integer" >&2
    exit 1
fi

# Check required tools.
command -v ffmpeg >/dev/null 2>&1 || {
    echo "Error: ffmpeg not found" >&2
    exit 1
}

command -v ffprobe >/dev/null 2>&1 || {
    echo "Error: ffprobe not found" >&2
    exit 1
}

command -v awk >/dev/null 2>&1 || {
    echo "Error: awk not found" >&2
    exit 1
}

# Derive output directory from the input video.
INPUT_DIR="$(dirname "$INPUT")"
INPUT_FILENAME="$(basename "$INPUT")"
INPUT_STEM="${INPUT_FILENAME%.*}"

OUTPUT_DIR="${INPUT_DIR}/${INPUT_STEM}_frames"
TIMESTAMP_FILE="${OUTPUT_DIR}/timestamps.csv"

mkdir -p "$OUTPUT_DIR"

# Get video duration in seconds.
DURATION="$(
    ffprobe \
        -v error \
        -select_streams v:0 \
        -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 \
        "$INPUT"
)"

if [[ -z "$DURATION" || "$DURATION" == "N/A" ]]; then
    echo "Error: could not determine video duration." >&2
    exit 1
fi

echo "Input:       $INPUT"
echo "Duration:    ${DURATION}s"
echo "Frames:      $NUM_FRAMES"
echo "Output:      $OUTPUT_DIR"
echo

# Remove previous output from an earlier run.
rm -f "$OUTPUT_DIR"/frame_*.jpg
rm -f "$TIMESTAMP_FILE"

# CSV header.
printf 'frame_id,timestamp_seconds,timestamp\n' > "$TIMESTAMP_FILE"

# Generate NUM_FRAMES timestamps uniformly across the video.
#
# The first frame is at t=0.
# The last frame is placed just before EOF rather than exactly at EOF,
# since requesting a frame at the exact duration can fail for some videos.
#
# This is timestamp-based rather than frame-number-based, so it does not
# depend on the video being constant-frame-rate.
awk \
    -v duration="$DURATION" \
    -v n="$NUM_FRAMES" '
BEGIN {
    for (i = 0; i < n; i++) {

        if (n == 1) {
            t = 0
        } else {
            t = duration * i / n
        }

        if (t < 0) {
            t = 0
        }

        printf "frame_%04d,%.6f\n", i + 1, t
    }
}
' |
while IFS=',' read -r FRAME_ID TIMESTAMP_SECONDS; do

    OUTPUT_FILE="${OUTPUT_DIR}/${FRAME_ID}.jpg"

    # Timestamp-based frame extraction.
    #
    # -ss after -i gives accurate timestamp seeking.
    # -frames:v 1 extracts exactly one frame.
    # -q:v 2 gives high-quality JPEG output.
    ffmpeg \
        -hide_banner \
        -loglevel error \
        -nostdin \
        -i "$INPUT" \
        -ss "$TIMESTAMP_SECONDS" \
        -frames:v 1 \
        -q:v 2 \
        "$OUTPUT_FILE"

    # Human-readable timestamp for convenient manual inspection.
    HUMAN_TIMESTAMP="$(
        awk -v t="$TIMESTAMP_SECONDS" '
        BEGIN {
            hours = int(t / 3600)
            minutes = int((t - hours * 3600) / 60)
            seconds = t - hours * 3600 - minutes * 60

            printf "%02d:%02d:%06.3f",
                   hours, minutes, seconds
        }
        '
    )"

    printf '%s,%s,%s\n' \
        "$FRAME_ID" \
        "$TIMESTAMP_SECONDS" \
        "$HUMAN_TIMESTAMP" \
        >> "$TIMESTAMP_FILE"

    echo "Extracted ${FRAME_ID}.jpg @ ${HUMAN_TIMESTAMP}"
done

echo
echo "Done."
echo "Frames:     $OUTPUT_DIR"
echo "Timestamps: $TIMESTAMP_FILE"
