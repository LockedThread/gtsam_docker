#!/usr/bin/env bash
# Run a validation script inside a GTSAM runtime container.
#
# Usage:
#   ./scripts/validate_container.sh [IMAGE_TAG] [EXAMPLE]
#
# Examples:
#   ./scripts/validate_container.sh
#   ./scripts/validate_container.sh gtsam_docker:latest
#   ./scripts/validate_container.sh gtsam_docker:latest /examples/PlanarSLAMExample.py
#   PYTHON_CMD=/usr/local/bin/python3 ./scripts/validate_container.sh image /examples/validate_numpy_abi.py

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXAMPLES_DIR="$REPO_ROOT/examples"
IMAGE="${1:-gtsam_docker:latest}"
EXAMPLE="${2:-/examples/validate_gtsam.py}"
PYTHON_CMD="${PYTHON_CMD:-/usr/local/bin/python3}"

if [[ -n "$EXAMPLE" && "$EXAMPLE" != /* ]]; then
  EXAMPLE="/examples/$EXAMPLE"
fi

if [[ ! -d "$EXAMPLES_DIR" ]]; then
  echo "ERROR: Examples directory not found: $EXAMPLES_DIR" >&2
  exit 1
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Image $IMAGE not found. Build it first." >&2
  exit 1
fi

echo "Running container validation (image: $IMAGE, script: $EXAMPLE, python: $PYTHON_CMD)..."
echo "---"

docker run --rm \
  -v "$EXAMPLES_DIR:/examples:ro" \
  "$IMAGE" \
  "$PYTHON_CMD" "$EXAMPLE"

status=$?
echo "---"
if [[ $status -eq 0 ]]; then
  echo "OK: validation finished with exit code 0."
else
  echo "FAIL: validation exited with code $status." >&2
  exit "$status"
fi
