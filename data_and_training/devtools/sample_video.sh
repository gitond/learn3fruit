#!/usr/bin/env bash

set -euo pipefail

# Generate uniformly distributed and high-value JPEG frames from a video.
#
# Usage:
#   ./data_and_training/devtools/sample_video.sh VIDEO [NUMBER_OF_FRAMES]
#
# Example:
#   ./data_and_training/devtools/sample_video.sh \
#       data_and_training/data/myvideotest/sample.mp4
#
# Default number of uniformly distributed frames: 130
#
# High-value intervals are sampled at exactly 1 FPS.
# Interval semantics are [start, end): start is included, end is excluded.
#
# Edit HV_INTERVALS below to configure high-value intervals.
# Leave it empty to disable high-value sampling.
#
# Output is placed next to the input video:
#   <video>_frames/
#       uniform_0001.jpg
#       ...
#       hv_0001.jpg
#       ...
#       timestamps.csv

INPUT="${1:?Usage: $0 VIDEO [NUMBER_OF_FRAMES]}"
NUM_FRAMES="${2:-130}"

# High-value intervals, sampled at exactly 1 FPS.
#
# Format:
#   "START,END" "START,END" ...
#
# START and END may be written as seconds or HH:MM:SS.
# Intervals use [start, end) semantics:
#   00:15-00:30 -> timestamps 15,16,...,29
#
# Leave empty for no high-value sampling.
HV_INTERVALS=(
    "00:00:15,00:00:30"
    "00:01:06,00:01:11"
    "00:08:18,00:08:28"
    "00:12:25,00:12:30"
    "00:13:37,00:13:52"
    "00:18:35,00:18:45"
    "00:21:24,00:21:29"
    "00:00:46,00:00:51"
)

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
echo "Uniform:     $NUM_FRAMES frames"
echo "HV intervals: ${#HV_INTERVALS[@]}"
echo "Output:      $OUTPUT_DIR"
echo

# Remove previous output from an earlier run.
rm -f "$OUTPUT_DIR"/uniform_*.jpg
rm -f "$OUTPUT_DIR"/hv_*.jpg
rm -f "$TIMESTAMP_FILE"

# CSV header.
printf 'frame_id,timestamp_seconds,timestamp\n' > "$TIMESTAMP_FILE"

# Convert a timestamp written as seconds or HH:MM:SS[.mmm] to seconds.
timestamp_to_seconds() {
    local value="$1"

    if [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        printf '%s\n' "$value"
        return
    fi

    if [[ "$value" =~ ^([0-9]+):([0-9]{2}):([0-9]{2})([.][0-9]+)?$ ]]; then
        awk \
            -v h="${BASH_REMATCH[1]}" \
            -v m="${BASH_REMATCH[2]}" \
            -v s="${BASH_REMATCH[3]}${BASH_REMATCH[4]}" '
            BEGIN {
                printf "%.6f\n", h * 3600 + m * 60 + s
            }
            '
        return
    fi

    echo "Error: invalid timestamp: $value" >&2
    exit 1
}

# Build the complete sample list before extracting anything.
#
# This is important: deduplication happens at the timestamp level first,
# so one timestamp can never receive two different frame IDs.
declare -A TIMESTAMP_TO_METHOD
declare -A TIMESTAMP_TO_ID
SAMPLE_TIMESTAMPS=()
SAMPLE_METHODS=()

add_sample() {
    local method="$1"
    local frame_id="$2"
    local timestamp="$3"

    # Normalize timestamp to six decimal places for deduplication.
    local key
    key="$(awk -v t="$timestamp" 'BEGIN { printf "%.6f", t }')"

    if [[ -n "${TIMESTAMP_TO_METHOD[$key]+x}" ]]; then
        return
    fi

    TIMESTAMP_TO_METHOD["$key"]="$method"
    TIMESTAMP_TO_ID["$key"]="$frame_id"
    SAMPLE_TIMESTAMPS+=("$key")
    SAMPLE_METHODS+=("$method")
}

# Generate uniform timestamps.
while IFS= read -r SAMPLE; do
    FRAME_ID="${SAMPLE%%,*}"
    TIMESTAMP_SECONDS="${SAMPLE#*,}"
    add_sample "uniform" "$FRAME_ID" "$TIMESTAMP_SECONDS"
done < <(
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

            printf "uniform_%04d,%.6f\n", i + 1, t
        }
    }
    '
)

# Generate high-value timestamps at exactly 1 FPS.
#
# For [start, end), integer timestamps are generated at:
#   ceil(start), ceil(start)+1, ..., ceil(end)-1
#
# This gives exactly one sample per whole second contained in the interval.
HV_COUNTER=0

for INTERVAL in "${HV_INTERVALS[@]}"; do
    START="${INTERVAL%%,*}"
    END="${INTERVAL#*,}"

    START_SECONDS="$(timestamp_to_seconds "$START")"
    END_SECONDS="$(timestamp_to_seconds "$END")"

    if ! awk -v start="$START_SECONDS" -v end="$END_SECONDS" '
        BEGIN { exit !(end > start) }
    '; then
        echo "Error: invalid high-value interval: $INTERVAL" >&2
        exit 1
    fi

    while IFS= read -r TIMESTAMP_SECONDS; do
        HV_COUNTER=$((HV_COUNTER + 1))
        FRAME_ID="$(printf 'hv_%04d' "$HV_COUNTER")"
        add_sample "hv" "$FRAME_ID" "$TIMESTAMP_SECONDS"
    done < <(
        awk \
            -v start="$START_SECONDS" \
            -v end="$END_SECONDS" '
        BEGIN {
            first = int(start)
            if (start > first) {
                first++
            }

            last = int(end - 0.000001)

            for (t = first; t <= last; t++) {
                if (t >= start && t < end) {
                    printf "%.6f\n", t
                }
            }
        }
        '
    )
done

echo "Samples after timestamp deduplication: ${#SAMPLE_TIMESTAMPS[@]}"
echo

# Extract the deduplicated sample list in sampling order.
#
# CSV is appended only after a successful extraction, so it always reflects
# frames that were actually generated if the script stops part-way through.
for ((i = 0; i < ${#SAMPLE_TIMESTAMPS[@]}; i++)); do
    TIMESTAMP_SECONDS="${SAMPLE_TIMESTAMPS[$i]}"
    METHOD="${SAMPLE_METHODS[$i]}"
    FRAME_ID="${TIMESTAMP_TO_ID[$TIMESTAMP_SECONDS]}"

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
