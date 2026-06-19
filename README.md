# gtsam_docker

Layered CI images for GTSAM Python bindings across multiple Python, GTSAM, base-image, and architecture combinations.

Published image families are built for `linux/amd64` and `linux/arm64`:

| Family | Tags |
|--------|------|
| `ghcr.io/<org>/<repo>/python-build` | `py<version>-glibc-trixie`, `py<version>-musl-alpine` |
| `ghcr.io/<org>/<repo>/python-runtime` | `py<version>-glibc-trixie`, `py<version>-glibc-trixie-slim`, `py<version>-musl-alpine` |
| `ghcr.io/<org>/<repo>/gtsam-build` | `gtsam<version>-py<version>-glibc-trixie`, `gtsam<version>-py<version>-musl-alpine` |
| `ghcr.io/<org>/<repo>` | `gtsam<version>-py<version>-trixie`, `gtsam<version>-py<version>-trixie-slim`, `gtsam<version>-py<version>-distroless-debian13`, `gtsam<version>-py<version>-alpine` |

Default matrix axes:

- Python: `3.11`, `3.12`, `3.13`, `3.14`
- GTSAM: `4.2.0`, `4.2.1`, `4.3a1`
- Runtime bases: Debian trixie, Debian trixie slim, distroless Debian 13, Alpine
- Architectures: `linux/amd64`, `linux/arm64`

`latest` remains a compatibility alias for the default Debian slim runtime: `gtsam4.3a1-py3.14-trixie-slim`.

## Local build

Build a local Python base, then build a GTSAM runtime from it:

```bash
docker build -f Dockerfile.python-base \
  --target python-build-glibc \
  --build-arg PYTHON_VERSION=3.14 \
  -t python-build:py3.14-glibc-trixie .

docker build -f Dockerfile.python-base \
  --target python-runtime-glibc-slim \
  --build-arg PYTHON_VERSION=3.14 \
  -t python-runtime:py3.14-glibc-trixie-slim .

docker build \
  --target runtime-trixie-slim \
  --build-arg PYTHON_VERSION=3.14 \
  --build-arg PYTHON_ABI=3.14 \
  --build-arg GTSAM_VERSION=4.3a1 \
  --build-arg PYTHON_BUILD_IMAGE=python-build:py3.14-glibc-trixie \
  --build-arg PYTHON_RUNTIME_SLIM_IMAGE=python-runtime:py3.14-glibc-trixie-slim \
  -t gtsam_docker:latest .
```

For Alpine, use `python-build-musl`, `python-runtime-musl-alpine`, and `--target runtime-alpine`. Alpine jobs are currently experimental in CI.

## Validate a container

```bash
./scripts/validate_container.sh gtsam_docker:latest /examples/validate_gtsam.py
./scripts/validate_container.sh gtsam_docker:latest /examples/validate_numpy_abi.py
./scripts/validate_container.sh gtsam_docker:latest /examples/PlanarSLAMExample.py
```

The validation script uses vector-form Docker commands and `/usr/local/bin/python3`, so it works with distroless images that do not include a shell.

## CI policy

Pull requests run a tiered smoke matrix:

- Blocking: `4.2.0` + Python `3.11` on trixie slim amd64.
- Blocking: `4.3a1` + Python `3.14` on trixie slim amd64 and arm64.
- Non-blocking: `4.3a1` + Python `3.14` on distroless and Alpine amd64.

The full scheduled/manual/release workflow publishes the complete matrix. GTSAM `4.2.x` with Python `3.13`/`3.14` and all Alpine runtimes are allowed-failure until those compatibility paths are stable.

## Size and dependency audits

Report local image size and compare against committed baselines:

```bash
./scripts/size-report.sh gtsam_docker:latest gtsam4.3a1-py3.14-trixie-slim
```

Baselines live in `ci/size-baselines.txt` and should be filled after the first successful full publish. Later CI runs fail images that grow more than 10% over their baseline.

Audit linked runtime dependencies for a build artifact image:

```bash
docker build --target gtsam-build -t gtsam-build \
  --build-arg PYTHON_BUILD_IMAGE=python-build:py3.14-glibc-trixie \
  --build-arg PYTHON_VERSION=3.14 \
  --build-arg PYTHON_ABI=3.14 \
  --build-arg GTSAM_VERSION=4.3a1 \
  .

./scripts/audit-runtime-deps.sh gtsam-build 3.14
```
