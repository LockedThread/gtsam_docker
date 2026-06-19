#!/usr/bin/env bash
set -u

JOBS="${JOBS:-2}"
DOCKER_BUILD_FLAGS="${DOCKER_BUILD_FLAGS:---progress=plain}"
export DOCKER_BUILD_FLAGS

PYTHONS="3.11 3.12 3.13 3.14"
GTSAMS="4.2.0 4.2.1 4.3a1"
RUNTIMES="trixie trixie-slim distroless-debian13 alpine"

build_base() {
  py="$1"
  docker build $DOCKER_BUILD_FLAGS -f Dockerfile.python-base --target python-build-glibc \
    --build-arg PYTHON_VERSION="$py" -t "python-build-local:py${py}-glibc-trixie" .
  docker build $DOCKER_BUILD_FLAGS -f Dockerfile.python-base --target python-runtime-glibc-trixie \
    --build-arg PYTHON_VERSION="$py" -t "python-runtime-local:py${py}-glibc-trixie" .
  docker build $DOCKER_BUILD_FLAGS -f Dockerfile.python-base --target python-runtime-glibc-slim \
    --build-arg PYTHON_VERSION="$py" -t "python-runtime-local:py${py}-glibc-trixie-slim" .
  docker build $DOCKER_BUILD_FLAGS -f Dockerfile.python-base --target python-build-musl \
    --build-arg PYTHON_VERSION="$py" -t "python-build-local:py${py}-musl-alpine" .
  docker build $DOCKER_BUILD_FLAGS -f Dockerfile.python-base --target python-runtime-musl-alpine \
    --build-arg PYTHON_VERSION="$py" -t "python-runtime-local:py${py}-musl-alpine" .
}

build_artifact() {
  py="$1"
  gtsam="$2"
  libc="$3"

  case "$libc" in
    glibc) suffix=glibc-trixie ;;
    musl) suffix=musl-alpine ;;
  esac

  docker build $DOCKER_BUILD_FLAGS \
    --target gtsam-build \
    --build-arg PYTHON_VERSION="$py" \
    --build-arg PYTHON_ABI="$py" \
    --build-arg GTSAM_VERSION="$gtsam" \
    --build-arg PYTHON_BUILD_IMAGE="python-build-local:py${py}-${suffix}" \
    -t "gtsam-build-local:gtsam${gtsam}-py${py}-${suffix}" .
}

build_validate_runtime() {
  py="$1"
  gtsam="$2"
  runtime="$3"

  case "$runtime" in
    trixie)
      target=runtime-trixie
      build_suffix=glibc-trixie
      runtime_suffix=glibc-trixie
      ;;
    trixie-slim)
      target=runtime-trixie-slim
      build_suffix=glibc-trixie
      runtime_suffix=glibc-trixie-slim
      ;;
    distroless-debian13)
      target=runtime-distroless
      build_suffix=glibc-trixie
      runtime_suffix=glibc-trixie-slim
      ;;
    alpine)
      target=runtime-alpine
      build_suffix=musl-alpine
      runtime_suffix=musl-alpine
      ;;
  esac

  tag="gtsam_docker:gtsam${gtsam}-py${py}-${runtime}"

  docker build $DOCKER_BUILD_FLAGS \
    --target "$target" \
    --build-arg PYTHON_VERSION="$py" \
    --build-arg PYTHON_ABI="$py" \
    --build-arg GTSAM_VERSION="$gtsam" \
    --build-arg PYTHON_BUILD_IMAGE="python-build-local:py${py}-${build_suffix}" \
    --build-arg PYTHON_RUNTIME_TRIXIE_IMAGE="python-runtime-local:py${py}-${runtime_suffix}" \
    --build-arg PYTHON_RUNTIME_SLIM_IMAGE="python-runtime-local:py${py}-${runtime_suffix}" \
    --build-arg PYTHON_RUNTIME_ALPINE_IMAGE="python-runtime-local:py${py}-${runtime_suffix}" \
    -t "$tag" .

  ./scripts/validate_container.sh "$tag" /examples/validate_gtsam.py
  ./scripts/validate_container.sh "$tag" /examples/validate_numpy_abi.py
  ./scripts/validate_container.sh "$tag" /examples/PlanarSLAMExample.py
  ./scripts/size-report.sh "$tag" "gtsam${gtsam}-py${py}-${runtime}"
}

export -f build_base build_artifact build_validate_runtime

printf "%s\n" $PYTHONS \
  | xargs -n 1 -P "$JOBS" bash -c 'build_base "$0"'

for py in $PYTHONS; do
  for gtsam in $GTSAMS; do
    printf "%s %s glibc\n%s %s musl\n" "$py" "$gtsam" "$py" "$gtsam"
  done
done | xargs -n 3 -P "$JOBS" bash -c 'build_artifact "$0" "$1" "$2"'

for py in $PYTHONS; do
  for gtsam in $GTSAMS; do
    for runtime in $RUNTIMES; do
      printf "%s %s %s\n" "$py" "$gtsam" "$runtime"
    done
  done
done | xargs -n 3 -P "$JOBS" bash -c 'build_validate_runtime "$0" "$1" "$2"'