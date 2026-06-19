# GTSAM build artifact and runtime images.
#
# Common targets:
#   gtsam-build          build artifact image with GTSAM installed into /usr/local
#   runtime-trixie       final runtime on python-runtime:*-glibc-trixie
#   runtime-trixie-slim  final runtime on python-runtime:*-glibc-trixie-slim
#   runtime-distroless   final runtime on gcr.io/distroless/cc-debian13
#   runtime-alpine       final runtime on python-runtime:*-musl-alpine
#   runtime              alias for runtime-trixie-slim
ARG PYTHON_VERSION=3.14
ARG PYTHON_ABI=${PYTHON_VERSION}
ARG GTSAM_VERSION=4.3a1
ARG NUMPY_SPEC=
ARG PYTHON_BUILD_IMAGE=python-build:py3.14-glibc-trixie
ARG PYTHON_RUNTIME_IMAGE=python-runtime:py3.14-glibc-trixie-slim
ARG PYTHON_RUNTIME_TRIXIE_IMAGE=python-runtime:py3.14-glibc-trixie
ARG PYTHON_RUNTIME_SLIM_IMAGE=python-runtime:py3.14-glibc-trixie-slim
ARG PYTHON_RUNTIME_ALPINE_IMAGE=python-runtime:py3.14-musl-alpine

FROM alpine/git:2.52.0@sha256:4a0e72d49596a1f5d3701aeedafdadc5c0da4062be4657c7bdc4017387f591cc AS gtsam-source
ARG GTSAM_VERSION
WORKDIR /usr/src
RUN git clone --quiet --depth 1 --branch "${GTSAM_VERSION}" https://github.com/borglab/gtsam.git

FROM ${PYTHON_BUILD_IMAGE} AS gtsam-build
ARG GTSAM_VERSION
ARG NUMPY_SPEC
ENV LD_LIBRARY_PATH=/usr/local/lib \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONUSERBASE=/usr/local \
    PIP_CONSTRAINT=/etc/pip-constraints.txt
COPY ci/requirements-build.txt /etc/pip-constraints.txt
COPY --from=gtsam-source /usr/src/gtsam /usr/src/gtsam
WORKDIR /usr/src/gtsam/build
# numpy major is an ABI choice tied to the GTSAM version, so it stays a range
# here (verified at runtime by validate_numpy_abi.py). Everything else
# (pyparsing, pybind11_stubgen, pip/setuptools/wheel) is version-pinned via
# the PIP_CONSTRAINT file above.
RUN set -eu; \
    resolved_numpy_spec="${NUMPY_SPEC}"; \
    resolved_pybind11_stubgen=""; \
    if [ -z "$resolved_numpy_spec" ]; then \
      case "$GTSAM_VERSION" in \
        4.3*) resolved_numpy_spec="numpy>=2,<3"; resolved_pybind11_stubgen="pybind11_stubgen" ;; \
        *) resolved_numpy_spec="numpy<2" ;; \
      esac; \
    fi; \
    python3 -m pip install -q --no-cache-dir -r /usr/src/gtsam/python/requirements.txt; \
    python3 -m pip install -q --no-cache-dir pyparsing "$resolved_numpy_spec" $resolved_pybind11_stubgen;
RUN set -eu; \
    cmake_log=/tmp/gtsam-cmake-configure.log; \
    python_exe="$(command -v python3)"; \
    python_include="$(python3 -c 'import sysconfig; print(sysconfig.get_path("include"))')"; \
    python_library="$(python3 -c 'import pathlib, sysconfig; print(pathlib.Path(sysconfig.get_config_var("LIBDIR"), sysconfig.get_config_var("LDLIBRARY")))')"; \
    if ! cmake \
      -Wno-dev \
      -Wno-deprecated \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DPython3_EXECUTABLE="$python_exe" \
      -DPython3_INCLUDE_DIR="$python_include" \
      -DPython3_LIBRARY="$python_library" \
      -DPython_EXECUTABLE="$python_exe" \
      -DPYTHON_EXECUTABLE="$python_exe" \
      -DPYTHON_INCLUDE_DIR="$python_include" \
      -DPYTHON_LIBRARY="$python_library" \
      -DGTSAM_WITH_EIGEN_MKL=OFF \
      -DGTSAM_BUILD_EXAMPLES_ALWAYS=OFF \
      -DGTSAM_BUILD_TIMING_ALWAYS=OFF \
      -DGTSAM_BUILD_TESTS=OFF \
      -DGTSAM_BUILD_PYTHON=ON \
      -DGTSAM_BUILD_CONVENIENCE_LIBRARIES=OFF \
      -DGTSAM_USE_SYSTEM_EIGEN=ON \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
      .. > "$cmake_log" 2>&1; then \
      cat "$cmake_log"; \
      exit 1; \
    fi; \
    rm -f "$cmake_log"
RUN set -eu; \
    cmake --build . --parallel "$(nproc)" -- -s; \
    cmake --build . --target install -- -s; \
    cmake --build . --target python-install -- -s; \
    find /usr/local -type f \( -name '*.so' -o -name '*.so.*' \) -exec strip --strip-unneeded {} + 2>/dev/null || true; \
    find /usr/local -type f -name '*.a' -delete; \
    python_site="$(python3 -c 'import site; print(site.getsitepackages()[0])')"; \
    for pkg in pip setuptools wheel packaging pytest _pytest pluggy iniconfig pygments py pybind11_stubgen; do \
      rm -rf "$python_site/$pkg" "$python_site/$pkg".* "$python_site/$pkg"-*.dist-info; \
    done; \
    find /usr/local -type d \( -name '__pycache__' -o -name 'test' -o -name 'tests' \) -prune -exec rm -rf {} +; \
    rm -rf /usr/src/gtsam /tmp/* /var/tmp/*
CMD ["python3"]

# Collect the exact set of third-party shared libraries the built GTSAM
# extensions link against (Boost, TBB, libstdc++, libgcc, ...), resolved
# dynamically via ldd so the list cannot drift when a base image bumps a
# Boost/TBB SONAME. Core libc/loader libraries are skipped because every
# runtime base already provides them. Original paths are preserved so the
# loader finds them with no ldconfig (needed for distroless).
FROM gtsam-build AS runtime-libs
RUN set -eu; \
    mkdir -p /runtime-libs; \
    targets="$(find /usr/local/lib -maxdepth 1 -name 'lib*gtsam*.so*' 2>/dev/null; \
               find /usr/local/lib/python*/site-packages/gtsam* -name '*.so' 2>/dev/null)"; \
    for so in $targets; do ldd "$so" 2>/dev/null || true; done \
      | awk '/=> \// {print $3}' | sort -u \
      | while IFS= read -r dep; do \
          [ -n "$dep" ] || continue; \
          case "$dep" in \
            /usr/local/*) continue ;; \
            */ld-linux*|*/ld-musl*|*/libc.so*|*/libm.so*|*/libdl.so*|*/libpthread.so*|*/librt.so*|*/libresolv.so*|*/libutil.so*) continue ;; \
          esac; \
          [ -e "$dep" ] || continue; \
          real="$(readlink -f "$dep")"; \
          dest="/runtime-libs$(dirname "$real")"; \
          mkdir -p "$dest"; \
          cp "$real" "$dest/$(basename "$dep")"; \
        done

FROM ${PYTHON_RUNTIME_TRIXIE_IMAGE} AS runtime-trixie
ARG PYTHON_ABI
ENV LD_LIBRARY_PATH=/usr/local/lib \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
COPY --from=runtime-libs /runtime-libs/ /
COPY --from=gtsam-build /usr/local/lib/lib*gtsam* /usr/local/lib/
COPY --from=gtsam-build /usr/local/lib/python${PYTHON_ABI}/site-packages /usr/local/lib/python${PYTHON_ABI}/site-packages
RUN ldconfig && \
    find /usr/local -type d -name '__pycache__' -prune -exec rm -rf {} + && \
    find /usr/local -type f -name '*.a' -delete
CMD ["python3"]

FROM ${PYTHON_RUNTIME_SLIM_IMAGE} AS runtime-trixie-slim
ARG PYTHON_ABI
ENV LD_LIBRARY_PATH=/usr/local/lib \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
COPY --from=runtime-libs /runtime-libs/ /
COPY --from=gtsam-build /usr/local/lib/lib*gtsam* /usr/local/lib/
COPY --from=gtsam-build /usr/local/lib/python${PYTHON_ABI}/site-packages /usr/local/lib/python${PYTHON_ABI}/site-packages
RUN ldconfig && \
    find /usr/local -type d -name '__pycache__' -prune -exec rm -rf {} + && \
    find /usr/local -type f -name '*.a' -delete
CMD ["python3"]

FROM ${PYTHON_RUNTIME_ALPINE_IMAGE} AS runtime-alpine
ARG PYTHON_ABI
ENV LD_LIBRARY_PATH=/usr/local/lib \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
COPY --from=runtime-libs /runtime-libs/ /
COPY --from=gtsam-build /usr/local/lib/lib*gtsam* /usr/local/lib/
COPY --from=gtsam-build /usr/local/lib/python${PYTHON_ABI}/site-packages /usr/local/lib/python${PYTHON_ABI}/site-packages
RUN find /usr/local -type d -name '__pycache__' -prune -exec rm -rf {} + && \
    find /usr/local -type f -name '*.a' -delete
CMD ["python3"]

# The distroless base has no package manager, so stage the CPython interpreter
# (installed under /usr/local in the python base image) plus CA certificates.
# Third-party shared libs come from the runtime-libs collector below.
FROM ${PYTHON_RUNTIME_SLIM_IMAGE} AS distroless-rootfs
RUN set -eu; \
    mkdir -p /rootfs/usr/local; \
    cp -a /usr/local/. /rootfs/usr/local/; \
    mkdir -p /rootfs/etc/ssl; \
    cp -a /etc/ssl/certs /rootfs/etc/ssl/certs; \
    find /rootfs/usr/local -type d -name '__pycache__' -prune -exec rm -rf {} +; \
    find /rootfs/usr/local -type f -name '*.a' -delete

FROM gcr.io/distroless/cc-debian13@sha256:a017e74bd2a12d98342dbecd33d121d2b160415ed777573dc1808969e989d94d AS runtime-distroless
ARG PYTHON_ABI
ENV LD_LIBRARY_PATH=/usr/local/lib \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
COPY --from=distroless-rootfs /rootfs /
COPY --from=runtime-libs /runtime-libs/ /
COPY --from=gtsam-build /usr/local/lib/lib*gtsam* /usr/local/lib/
COPY --from=gtsam-build /usr/local/lib/python${PYTHON_ABI}/site-packages /usr/local/lib/python${PYTHON_ABI}/site-packages
CMD ["/usr/local/bin/python3"]

FROM runtime-trixie-slim AS runtime
