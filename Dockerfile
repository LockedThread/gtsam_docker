ARG PYTHON_VERSION

# Get the base python image from Docker Hub
FROM python:${PYTHON_VERSION}-bullseye as dependencies

# Disable GUI prompts
ENV DEBIAN_FRONTEND noninteractive

# Update apps on the base image
RUN apt-get -y update

# Install C++
RUN apt-get -y install build-essential apt-utils

# Install boost and cmake
RUN apt-get -y install libboost-all-dev cmake

# Install TBB
RUN apt-get -y install libtbb-dev

# Install GCC & Others
RUN apt-get -y install build-essential

# Use git to clone gtsam and specific GTSAM version 
FROM alpine/git:2.40.1 as gtsam-clone

ARG GTSAM_VERSION
WORKDIR /usr/src/

# Clone GTSAM and checkout to given GTSAM_VERSION tag
RUN git clone --no-checkout https://github.com/borglab/gtsam.git
WORKDIR /usr/src/gtsam
RUN git fetch origin tag ${GTSAM_VERSION}
RUN git checkout ${GTSAM_VERSION}

# Create new stage called gtsam for GTSAM building
FROM dependencies as gtsam

# Move gtsam data
COPY --from=gtsam-clone /usr/src/gtsam /usr/src/gtsam

WORKDIR /usr/src/gtsam/build

# Needed to link with GTSAM
RUN echo 'export LD_LIBRARY_PATH=/usr/local/lib:LD_LIBRARY_PATH' >> /root/.bashrc

# Install python wrapper requirements
RUN python3 -m pip install -U -r /usr/src/gtsam/python/requirements.txt

# Run cmake
RUN cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DGTSAM_WITH_EIGEN_MKL=OFF \
    -DGTSAM_BUILD_EXAMPLES_ALWAYS=OFF \
    -DGTSAM_BUILD_TIMING_ALWAYS=OFF \
    -DGTSAM_BUILD_TESTS=OFF \
    -DGTSAM_BUILD_PYTHON=ON \
    -DGTSAM_PYTHON_VERSION=${PYTHON_VERSION} \
    ..

RUN make -j4 install
RUN make python-install
RUN make clean

CMD ["bash"]
