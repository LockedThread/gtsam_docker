#!/usr/bin/env bash
# Report image size and optionally compare against a committed baseline.
#
# Baseline format: one image/tag key and size in bytes per line:
#   gtsam4.3a1-py3.14-trixie-slim 123456789
#
# Usage:
#   ./scripts/size-report.sh IMAGE [BASELINE_KEY] [BASELINE_FILE] [MAX_GROWTH_PERCENT]

set -euo pipefail

IMAGE="${1:?usage: scripts/size-report.sh IMAGE [BASELINE_KEY] [BASELINE_FILE] [MAX_GROWTH_PERCENT]}"
BASELINE_KEY="${2:-$IMAGE}"
BASELINE_FILE="${3:-ci/size-baselines.txt}"
MAX_GROWTH_PERCENT="${4:-10}"

size=""
if docker image inspect "$IMAGE" >/dev/null 2>&1; then
  size="$(docker image inspect --format '{{.Size}}' "$IMAGE")"
elif docker buildx imagetools inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Image is remote or multi-arch; docker buildx imagetools can inspect it, but local byte comparison requires a pulled single-platform image."
  docker buildx imagetools inspect "$IMAGE"
  exit 0
else
  echo "ERROR: image not found locally or remotely: $IMAGE" >&2
  exit 1
fi

echo "IMAGE_SIZE_BYTES $BASELINE_KEY $size"

if [[ ! -f "$BASELINE_FILE" ]]; then
  echo "No baseline file found at $BASELINE_FILE; skipping threshold check."
  exit 0
fi

baseline="$(awk -v key="$BASELINE_KEY" '$1 == key {print $2}' "$BASELINE_FILE" | tail -n 1)"
if [[ -z "$baseline" ]]; then
  echo "No baseline entry for $BASELINE_KEY; skipping threshold check."
  exit 0
fi

limit=$(( baseline + (baseline * MAX_GROWTH_PERCENT / 100) ))
if (( size > limit )); then
  echo "ERROR: $BASELINE_KEY grew from $baseline to $size bytes; allowed limit is $limit bytes (${MAX_GROWTH_PERCENT}%)." >&2
  exit 1
fi

echo "OK: $BASELINE_KEY is within ${MAX_GROWTH_PERCENT}% of baseline ($baseline bytes)."
