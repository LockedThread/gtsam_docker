FROM debian:bullseye as dependencies
ARG PYTHON_VERSION=3.11.2

# Disable GUI prompts
ENV DEBIAN_FRONTEND noninteractive


RUN rm /var/lib/dpkg/info/libc-bin.*
RUN apt-get clean && apt-get update
RUN apt-get -y install libc-bin

# Install required build dependencies
RUN apt-get update && apt-get install -y \
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
    && rm -rf /var/lib/apt/lists/*


# Download and build GCC 13.4
RUN wget https://ftp.gnu.org/gnu/gcc/gcc-13.4.0/gcc-13.4.0.tar.gz && \
    tar -xzf gcc-13.4.0.tar.gz && \
    cd gcc-13.4.0 && \
    ./contrib/download_prerequisites && \
    mkdir build && \
    cd build && \
    ../configure --prefix=/usr/local/gcc-13.4.0 \
                 --enable-languages=c,c++ \
                 --disable-multilib \
                 --disable-bootstrap \
                 --enable-checking=release && \
    make -j$(nproc) && \
    make install && \
    cd ../.. && \
    rm -rf gcc-13.4.0 gcc-13.4.0.tar.gz

# Set up GCC 13.4 as the default compiler
ENV PATH="/usr/local/gcc-13.4.0/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/local/gcc-13.4.0/lib64:${LD_LIBRARY_PATH}"
ENV CC="/usr/local/gcc-13.4.0/bin/gcc"
ENV CXX="/usr/local/gcc-13.4.0/bin/g++"

# Create symlinks for easier access
RUN ln -sf /usr/local/gcc-13.4.0/bin/gcc /usr/local/bin/gcc && \
    ln -sf /usr/local/gcc-13.4.0/bin/g++ /usr/local/bin/g++

# Install Make 4.4.1
RUN wget https://ftp.gnu.org/gnu/make/make-4.4.1.tar.gz && \
    tar -xzf make-4.4.1.tar.gz && \
    cd make-4.4.1 && \
    ./configure --prefix=/usr/local && \
    make -j$(nproc) && \
    make install && \
    cd .. && \
    rm -rf make-4.4.1 make-4.4.1.tar.gz

# Install CMake 4.0.3
RUN wget https://github.com/Kitware/CMake/releases/download/v4.0.3/cmake-4.0.3.tar.gz && \
    tar -xzf cmake-4.0.3.tar.gz && \
    cd cmake-4.0.3 && \
    ./bootstrap --prefix=/usr/local && \
    make -j$(nproc) && \
    make install && \
    cd .. && \
    rm -rf cmake-4.0.3 cmake-4.0.3.tar.gz

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

RUN python3 -m pip install --upgrade pip

# Use git to clone gtsam and specific GTSAM version 
FROM alpine/git:2.49.0 as gtsam-clone

ARG GTSAM_VERSION=4.2.0
WORKDIR /usr/src/

# Clone GTSAM and checkout to given GTSAM_VERSION tag
RUN git clone --no-checkout https://github.com/borglab/gtsam.git && \
    cd gtsam && \
    git fetch origin tag ${GTSAM_VERSION} && \
    git checkout ${GTSAM_VERSION}

# Create new stage called gtsam for GTSAM building
FROM dependencies as gtsam

# Move gtsam data
COPY --from=gtsam-clone /usr/src/gtsam /usr/src/gtsam

WORKDIR /usr/src/gtsam/build

# Needed to link with GTSAM
RUN echo "export LD_LIBRARY_PATH=/usr/local/lib:\$LD_LIBRARY_PATH" >> /root/.bashrc

# Install python wrapper requirements
RUN python3 -m pip install -U -r /usr/src/gtsam/python/requirements.txt

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

# Make install and clean up
RUN make -j$(nproc) install && \
    make python-install && \
    make clean

RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN ldconfig

CMD ["bash"]