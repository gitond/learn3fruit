#!/usr/bin/env bash
# gen_split.sh — Stratified train/val split for a multi-label Pascal VOC dataset.
#
# USAGE:
#   bash gen_split.sh DS_DIR MATCHLOG [SEED] [VAL_FRACTION]
#
# ARGUMENTS:
#   DS_DIR        Directory containing images/ subdirectory to split
#   MATCHLOG      Path to dlTIMESTAMPmatchlog.txt produced by prep_data_dl.sh
#   SEED          Integer seed for reproducible shuffling (default: 42)
#   VAL_FRACTION  Fraction to assign to val, truncated (default: 0.15)
#
# BEHAVIOUR:
#   Reads per-category image lists from MATCHLOG.  For each category, performs a
#   seeded shuffle and selects floor(N * VAL_FRACTION) candidates for val (where N
#   is the per-category image count).  The val set is the union of all per-category
#   candidates; multi-class images count toward every category they belong to.
#
#   If the union causes a category to exceed its val target (because a multi-class
#   image was pulled in via another category), single-class images are removed from
#   that category's val contribution in sorted order until the target is met.  If
#   the target still cannot be met (all surplus images are multi-class and shared),
#   a warning is emitted and the closest achievable count is used.
#
#   On completion, DS_DIR/images/ is removed and replaced by:
#     DS_DIR/train/images/
#     DS_DIR/val/images/

set -euo pipefail

usage() {
    grep '^#' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 1
}

[[ $# -lt 2 || $# -gt 4 ]] && usage

DS_DIR="${1%/}"
MATCHLOG="$2"
SEED="${3:-42}"
VAL_FRACTION="${4:-0.15}"

[[ -d "$DS_DIR/images" ]] || { echo "Error: $DS_DIR/images not found" >&2; exit 1; }
[[ -f "$MATCHLOG" ]]      || { echo "Error: matchlog not found: $MATCHLOG" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Parse matchlog
# ---------------------------------------------------------------------------
# Supports both the new format ("Category: N val, M train\n<split/id>\n...")
# and the old format ("Category\n<bare_id>\n...").
# Lines with a split prefix ("validation/" or "train/") have that prefix stripped.

declare -A cat_images=()   # category -> newline-delimited image IDs
declare -A image_cats=()   # image_id -> pipe-delimited category list
categories=()
current_cat=""

while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -z "$line" ]]; then
        current_cat=""
    elif [[ "$line" =~ ^([^/]+):[[:space:]]*[0-9]+[[:space:]]val ]]; then
        # New format title: "Apple: 50 val, 300 train"
        current_cat="${BASH_REMATCH[1]}"
        categories+=("$current_cat")
        cat_images["$current_cat"]=""
    elif [[ -n "$current_cat" && -z "${cat_images[$current_cat]+_}" ]] ||
         [[ -n "$current_cat" && ! "$line" =~ ^[^/]+:[[:space:]]*[0-9] ]]; then
        # Image ID line (may carry "validation/" or "train/" prefix)
        img_id="${line#*/}"
        [[ -z "$img_id" ]] && continue
        cat_images["$current_cat"]+="${img_id}"$'\n'
        if [[ -z "${image_cats[$img_id]+_}" ]]; then
            image_cats["$img_id"]="$current_cat"
        else
            image_cats["$img_id"]+="|$current_cat"
        fi
    fi
done < "$MATCHLOG"

[[ ${#categories[@]} -eq 0 ]] && {
    echo "Error: no categories parsed from $MATCHLOG" >&2; exit 1
}

# Derive per-category total from the first category
first_cat="${categories[0]}"
total_per_cat=$(printf '%s' "${cat_images[$first_cat]}" | grep -c '[^[:space:]]' || true)

# Val target: floor(total * fraction) — truncated so train set is never smaller than intended
val_target=$(awk -v n="$total_per_cat" -v f="$VAL_FRACTION" 'BEGIN { printf "%d", int(n * f) }')
train_target=$(( total_per_cat - val_target ))

echo "Per-category total: $total_per_cat  |  val target: $val_target  |  train target: $train_target"

# ---------------------------------------------------------------------------
# Build initial val set via per-category seeded shuffle
# ---------------------------------------------------------------------------
declare -A val_set=()    # image_id -> 1
declare -A val_count=()  # category -> count of category's images currently in val_set

for cat in "${categories[@]}"; do
    val_count["$cat"]=0
done

cat_idx=0
for cat in "${categories[@]}"; do
    # Append category index to base seed so each category gets a distinct shuffle
    cat_seed="${SEED}${cat_idx}"
    while IFS= read -r img; do
        [[ -z "$img" ]] && continue
        val_set["$img"]=1
    done < <(
        printf '%s' "${cat_images[$cat]}" \
            | grep '[^[:space:]]' \
            | shuf --random-source=<(yes "$cat_seed") \
            | head -n "$val_target"
    )
    (( cat_idx++ )) || true
done

# Count val images per category (multi-class images increment all their categories)
for img in "${!val_set[@]}"; do
    IFS='|' read -ra img_cat_list <<< "${image_cats[$img]}"
    for cat in "${img_cat_list[@]}"; do
        (( val_count[$cat]++ )) || true
    done
done

# ---------------------------------------------------------------------------
# Adjustment: fix over-represented categories
# ---------------------------------------------------------------------------
# A multi-class image selected by category A may also belong to B, causing B to
# exceed its target.  Remove single-class images from B in sorted (deterministic)
# order until the target is met or no single-class removals remain.
for cat in "${categories[@]}"; do
    while [[ ${val_count[$cat]} -gt $val_target ]]; do
        removed=false
        for img in $(printf '%s\n' "${!val_set[@]}" | sort); do
            # Must belong to the over-represented category
            [[ "|${image_cats[$img]}|" != *"|${cat}|"* ]] && continue
            # Must be single-class so removing it doesn't affect other categories
            IFS='|' read -ra img_cat_list <<< "${image_cats[$img]}"
            [[ ${#img_cat_list[@]} -ne 1 ]] && continue
            unset 'val_set[$img]'
            (( val_count[$cat]-- )) || true
            removed=true
            break
        done
        if [[ "$removed" != "true" ]]; then
            echo "Warning: cannot reach val target $val_target for '$cat'" \
                 "(best achievable: ${val_count[$cat]})" >&2
            break
        fi
    done
done

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
echo "Val set: ${#val_set[@]} unique images"
all_ok=true
for cat in "${categories[@]}"; do
    count="${val_count[$cat]}"
    if [[ "$count" -ne "$val_target" ]]; then
        printf "  %-24s %d val  [MISMATCH — target %d]\n" "$cat" "$count" "$val_target"
        all_ok=false
    else
        printf "  %-24s %d val  [ok]\n" "$cat" "$count"
    fi
done
[[ "$all_ok" == "true" ]] || echo "Warning: some categories did not reach the val target" >&2

# ---------------------------------------------------------------------------
# Move images
# ---------------------------------------------------------------------------
mkdir -p "$DS_DIR/train/images" "$DS_DIR/val/images"

n_train=0
n_val=0
for img_file in "$DS_DIR/images"/*.jpg "$DS_DIR/images"/*.jpeg; do
    [[ -f "$img_file" ]] || continue
    stem="${img_file##*/}"
    stem="${stem%.*}"
    if [[ "${val_set[$stem]+_}" ]]; then
        mv "$img_file" "$DS_DIR/val/images/"
        (( n_val++ )) || true
    else
        mv "$img_file" "$DS_DIR/train/images/"
        (( n_train++ )) || true
    fi
done

rmdir "$DS_DIR/images"
echo "Moved: $n_train → ds/train/images/  |  $n_val → ds/val/images/"
