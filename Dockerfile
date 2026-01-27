# Default build produces the "runtime" stage (slim). Use --target gtsam for a dev image with build tools and shell.
FROM debian:trixie-20260112 AS dependencies
ARG PYTHON_VERSION=3.11.2

# Disable GUI prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install required build dependencies (single update for better layer caching)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    build-essential \
    wget \
    libssl-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    libffi-dev \
    zlib1g-dev \
    libncursesw5-dev \
    tk-dev \
    libgdbm-dev \
    liblzma-dev \
    apt-utils \
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

# Install Python with --enable-shared
RUN wget https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz && \
    tar xvf Python-${PYTHON_VERSION}.tgz && \
    cd Python-${PYTHON_VERSION} && \
    ./configure --enable-optimizations --with-lto --enable-shared && \
    make -j$(nproc) && \
    make install && \
    cd .. && \
    rm -rf Python-${PYTHON_VERSION} Python-${PYTHON_VERSION}.tgz && \
    ldconfig

# Ensure /usr/local/bin is in the PATH
ENV PATH="/usr/local/bin:${PATH}"

RUN python3 -m pip install --no-cache-dir --upgrade pip

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

# Install python wrapper requirements
RUN python3 -m pip install --no-cache-dir -U -r /usr/src/gtsam/python/requirements.txt

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
    find /usr/local -type f \( -name "*.so" -o -name "*.so.*" \) -exec strip --strip-unneeded {} \; 2>/dev/null || true && \
    find /usr/local/bin /usr/local/lib -executable -type f -exec strip --strip-unneeded {} \; 2>/dev/null || true && \
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

# Runtime libs only (no -dev, no build-essential). Match what Python + GTSAM link to.
# Verify with: ldd /usr/local/lib/libgtsam.so /usr/local/bin/python3.11 (in build image)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3t64 \
    libbz2-1.0 \
    libreadline8t64 \
    libsqlite3-0 \
    libffi8 \
    zlib1g \
    libncursesw6 \
    libtbb12 \
    libgmp10 \
    libmpfr6 \
    libmpc3 \
    libboost-serialization1.83.0 \
    libboost-system1.83.0 \
    libboost-thread1.83.0 \
    libboost-date-time1.83.0 \
    libboost-filesystem1.83.0 \
    libboost-chrono1.83.0 \
    libboost-atomic1.83.0 \
    libboost-timer1.83.0 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=gtsam /usr/local /usr/local

RUN ldconfig

CMD ["python3"]