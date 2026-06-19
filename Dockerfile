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

FROM alpine/git:2.52.0 AS gtsam-source
ARG GTSAM_VERSION
WORKDIR /usr/src
RUN git clone --quiet --depth 1 --branch "${GTSAM_VERSION}" https://github.com/borglab/gtsam.git

FROM ${PYTHON_BUILD_IMAGE} AS gtsam-build
ARG GTSAM_VERSION
ARG NUMPY_SPEC
ENV LD_LIBRARY_PATH=/usr/local/lib \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
COPY --from=gtsam-source /usr/src/gtsam /usr/src/gtsam
WORKDIR /usr/src/gtsam/build
RUN set -eu; \
    resolved_numpy_spec="${NUMPY_SPEC}"; \
    if [ -z "$resolved_numpy_spec" ]; then \
      case "$GTSAM_VERSION" in \
        4.3*) resolved_numpy_spec='numpy>=2,<3' ;; \
        *) resolved_numpy_spec='numpy<2' ;; \
      esac; \
    fi; \
    python3 -m pip install -q --no-cache-dir --upgrade -r /usr/src/gtsam/python/requirements.txt; \
    python3 -m pip install -q --no-cache-dir --upgrade "$resolved_numpy_spec"
RUN set -eu; \
    cmake_log=/tmp/gtsam-cmake-configure.log; \
    if ! cmake \
      -Wno-dev \
      -Wno-deprecated \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
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
    rm -rf "$python_site"/pip* "$python_site"/setuptools* "$python_site"/wheel* "$python_site"/packaging*; \
    find /usr/local -type d \( -name '__pycache__' -o -name 'test' -o -name 'tests' \) -prune -exec rm -rf {} +; \
    rm -rf /usr/src/gtsam /tmp/* /var/tmp/*
CMD ["python3"]

FROM ${PYTHON_RUNTIME_TRIXIE_IMAGE} AS runtime-trixie
ARG PYTHON_ABI
ENV LD_LIBRARY_PATH=/usr/local/lib \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
COPY --from=gtsam-build /usr/local/lib/libgtsam* /usr/local/lib/
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
COPY --from=gtsam-build /usr/local/lib/libgtsam* /usr/local/lib/
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
COPY --from=gtsam-build /usr/local/lib/libgtsam* /usr/local/lib/
COPY --from=gtsam-build /usr/local/lib/python${PYTHON_ABI}/site-packages /usr/local/lib/python${PYTHON_ABI}/site-packages
RUN find /usr/local -type d -name '__pycache__' -prune -exec rm -rf {} + && \
    find /usr/local -type f -name '*.a' -delete
CMD ["python3"]

FROM ${PYTHON_RUNTIME_SLIM_IMAGE} AS distroless-rootfs
RUN set -eu; \
    mkdir -p /rootfs; \
    cp -a /usr/local /rootfs/usr-local; \
    mkdir -p /rootfs/usr/local; \
    cp -a /rootfs/usr-local/. /rootfs/usr/local/; \
    rm -rf /rootfs/usr-local; \
    for lib in \
      /usr/lib/*/libboost_*.so* \
      /usr/lib/*/libtbb*.so* \
      /usr/lib/*/libgomp*.so* \
      /usr/lib/*/libstdc++.so* \
      /usr/lib/*/libgcc_s.so*; do \
      [ -e "$lib" ] || continue; \
      cp -a --parents "$lib" /rootfs; \
    done; \
    mkdir -p /rootfs/etc/ssl; \
    cp -a /etc/ssl/certs /rootfs/etc/ssl/certs; \
    find /rootfs/usr/local -type d -name '__pycache__' -prune -exec rm -rf {} +; \
    find /rootfs/usr/local -type f -name '*.a' -delete

FROM gcr.io/distroless/cc-debian13 AS runtime-distroless
ARG PYTHON_ABI
ENV LD_LIBRARY_PATH=/usr/local/lib \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
COPY --from=distroless-rootfs /rootfs /
COPY --from=gtsam-build /usr/local/lib/libgtsam* /usr/local/lib/
COPY --from=gtsam-build /usr/local/lib/python${PYTHON_ABI}/site-packages /usr/local/lib/python${PYTHON_ABI}/site-packages
CMD ["/usr/local/bin/python3"]

FROM runtime-trixie-slim AS runtime
