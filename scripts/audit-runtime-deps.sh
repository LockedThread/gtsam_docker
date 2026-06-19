#!/usr/bin/env bash
# Find runtime .so dependencies used by Python + GTSAM in a built image.
#
# Usage:
#   ./scripts/audit-runtime-deps.sh [IMAGE] [PYTHON_ABI]
#
# Examples:
#   ./scripts/audit-runtime-deps.sh gtsam-build 3.14
#   ./scripts/audit-runtime-deps.sh ghcr.io/org/repo/gtsam-build:gtsam4.3a1-py3.14-glibc-trixie 3.14

set -euo pipefail

IMAGE="${1:-gtsam-build}"
PYTHON_ABI="${2:-}"

container_script='set -eu
python_bin="$(command -v python3 || true)"
if [ -z "$python_bin" ]; then
  python_bin=/usr/local/bin/python3
fi
python_abi="'"$PYTHON_ABI"'"
if [ -z "$python_abi" ]; then
  python_abi="$($python_bin -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")"
fi
files="$python_bin /usr/local/lib/libgtsam.so /usr/local/lib/libgtsam_unstable.so"
site_dir="/usr/local/lib/python${python_abi}/site-packages"
if [ -d "$site_dir/gtsam" ]; then
  files="$files $(find "$site_dir/gtsam" -type f -name "*.so" 2>/dev/null)"
fi
for f in $files; do
  [ -f "$f" ] && ldd "$f" 2>/dev/null || true
done
'

echo "=== 1. System shared libs actually linked (paths) ==="
docker run --rm "$IMAGE" sh -c "$container_script" \
  | awk '/=>/ {print $3}' \
  | grep -E '^/lib|^/usr/lib' \
  | sort -u || true

echo ""
echo "=== 2. Debian packages that provide those libs (if dpkg is available) ==="
docker run --rm "$IMAGE" sh -c "$container_script" \
  | awk '/=>/ {print $3}' \
  | grep -E '^/lib|^/usr/lib' \
  | sort -u \
  | while read -r p; do r="$(readlink -f "$p" 2>/dev/null || printf '%s' "$p")"; echo "$r"; done \
  | docker run --rm -i "$IMAGE" sh -c 'if command -v dpkg >/dev/null 2>&1; then xargs -r dpkg -S 2>/dev/null | cut -d: -f1 | sort -u; else cat >/dev/null; echo "dpkg unavailable in image"; fi' || true
