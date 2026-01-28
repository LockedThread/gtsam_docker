#!/usr/bin/env bash
# Run a GTSAM example inside the runtime container to validate the image.
#
# Usage:
#   ./scripts/validate_container.sh [IMAGE_TAG] [EXAMPLE]
#
# Examples:
#   ./scripts/validate_container.sh
#   ./scripts/validate_container.sh gtsam_docker:latest
#   ./scripts/validate_container.sh gtsam_docker:latest /examples/PlanarSLAMExample.py
#
# Default EXAMPLE is /examples/validate_gtsam.py (minimal graph/values check).
# Use /examples/PlanarSLAMExample.py for the full PlanarSLAM example from borglab/gtsam.
#
# Prereq: build the runtime image first, e.g.  docker build -t gtsam_docker:latest .

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXAMPLES_DIR="$REPO_ROOT/examples"
IMAGE="${1:-gtsam_docker:latest}"
EXAMPLE="${2:-/examples/validate_gtsam.py}"
# If EXAMPLE has no leading slash, treat as name under /examples/
if [[ -n "$EXAMPLE" && "$EXAMPLE" != /* ]]; then
  EXAMPLE="/examples/$EXAMPLE"
fi

if [[ ! -d "$EXAMPLES_DIR" ]]; then
  echo "ERROR: Examples directory not found: $EXAMPLES_DIR" >&2
  exit 1
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Image $IMAGE not found. Build it first, e.g.:" >&2
  echo "  docker build -t gtsam_docker:latest ." >&2
  exit 1
fi

echo "Running GTSAM example in container (image: $IMAGE, script: $EXAMPLE)..."
echo "---"

docker run --rm \
  -v "$EXAMPLES_DIR:/examples:ro" \
  "$IMAGE" \
  python3 "$EXAMPLE"

EXIT_CODE=$?
echo "---"
if [[ $EXIT_CODE -eq 0 ]]; then
  echo "OK: Example finished with exit code 0."
else
  echo "FAIL: Example exited with code $EXIT_CODE." >&2
  exit $EXIT_CODE
fi
