# Default build produces the "runtime" stage (slim). Use --target gtsam for a dev image with build tools and shell.
# Pre-built Python base image (build once with Dockerfile.python-base, push to registry)
# To build locally without registry: docker build -f Dockerfile.python-base -t python-optimized:3.11.2-trixie .
ARG PYTHON_BASE_IMAGE=python-optimized:3.11.2-trixie
FROM ${PYTHON_BASE_IMAGE} AS dependencies

# Disable GUI prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install GTSAM build dependencies (Python already installed in base image)
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-utils \
    build-essential \
    libboost-all-dev \
    cmake \
    libtbb-dev \
    flex \
    bison \
    dejagnu \
    libmpc-dev \
    libmpfr-dev \
    libgmp-dev \
    make \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /usr/src

# Use git to clone gtsam and specific GTSAM version 
FROM alpine/git:2.52.0 AS gtsam-clone

ARG GTSAM_VERSION=4.2.0
WORKDIR /usr/src/

# Shallow clone specific tag for smaller, faster fetch
RUN git clone --depth 1 --branch ${GTSAM_VERSION} https://github.com/borglab/gtsam.git

# Create new stage called gtsam for GTSAM building
FROM dependencies AS gtsam

ARG PYTHON_VERSION=3.11.2

# Needed to link with GTSAM (ENV works in non-interactive shells; .bashrc does not)
ENV LD_LIBRARY_PATH=/usr/local/lib

# Move gtsam data
COPY --from=gtsam-clone /usr/src/gtsam /usr/src/gtsam

WORKDIR /usr/src/gtsam/build

# Install python wrapper requirements, then pin numpy for GTSAM ABI compatibility
RUN python3 -m pip install --no-cache-dir -U -r /usr/src/gtsam/python/requirements.txt && \
    python3 -m pip install --no-cache-dir "numpy==1.26.4"

# Run cmake
RUN cmake \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DGTSAM_WITH_EIGEN_MKL=OFF \
    -DGTSAM_BUILD_EXAMPLES_ALWAYS=OFF \
    -DGTSAM_BUILD_TIMING_ALWAYS=OFF \
    -DGTSAM_BUILD_TESTS=OFF \
    -DGTSAM_BUILD_PYTHON=ON \
    -DGTSAM_BUILD_CONVENIENCE_LIBRARIES=OFF \
    -DGTSAM_PYTHON_VERSION=${PYTHON_VERSION} \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    ..

# Build, install, strip binaries, and clean in one layer to reduce image size
RUN make -j$(nproc) install && \
    make python-install && \
    #find /usr/local -type f \( -name "*.so" -o -name "*.so.*" \) -exec strip --strip-unneeded {} \; 2>/dev/null || true && \
    #find /usr/local/bin /usr/local/lib -executable -type f -exec strip --strip-unneeded {} \; 2>/dev/null || true && \
    make clean && \
    ldconfig

# Final cleanup (dependencies stage already cleared apt lists)
RUN rm -rf /tmp/* /var/tmp/*

# -----------------------------------------------------------------------------
# Slim runtime stage: copy only installed artifacts, no build tools or source
# -----------------------------------------------------------------------------
FROM debian:trixie-slim AS runtime

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/usr/local/bin:${PATH}"
ENV LD_LIBRARY_PATH=/usr/local/lib

# Runtime libs only. Python binary (ldd python3.11) needs only libc/libm/libpython; GTSAM needs Boost + TBB (see scripts/audit-runtime-deps.sh).
# Add back libssl3t64 libbz2-1.0 libreadline8t64 libsqlite3-0 libffi8 zlib1g libncursesw6 if you import ssl/sqlite3/readline/etc.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libtbb12 \
    libtbbmalloc2 \
    libboost-serialization1.83.0 \
    libboost-filesystem1.83.0 \
    libboost-timer1.83.0 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=gtsam /usr/local /usr/local

RUN ldconfig

CMD ["python3"]