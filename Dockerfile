ARG PYTHON_VERSION=3.11.2

# Get the base python image from Docker Hub
FROM python:${PYTHON_VERSION}-bullseye as dependencies

# Disable GUI prompts
ENV DEBIAN_FRONTEND noninteractive

# Update apps on the base image and install necessary packages
RUN apt-get -y update && \
    apt-get -y install build-essential apt-utils libboost-all-dev cmake libtbb-dev && \
    rm -rf /var/lib/apt/lists/*

# Use git to clone gtsam and specific GTSAM version 
FROM alpine/git:2.40.1 as gtsam-clone

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
    -DGTSAM_BUILD_CONVENIENCE_LIBRARIES=OFF \
    -DGTSAM_PYTHON_VERSION=${PYTHON_VERSION} \
    ..

# Make install and clean up
RUN make -j4 install && \
    make python-install && \
    make clean

RUN python3 python/setup.py bdist_wheel

RUN cp /usr/src/gtsam/build/dist/gtsam-4.2a9-py3-none-any.whl /usr/gtsam-4.2a9-py3-none-any.whl

RUN rm -rf /usr/src/gtsam/

RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Get the base python image from Docker Hub
FROM python:${PYTHON_VERSION}-slim-bullseye as runtime

COPY --from=gtsam /usr/gtsam-4.2a9-py3-none-any.whl /gtsam-4.2a9-py3-none-any.whl

RUN pip install /gtsam-4.2a9-py3-none-any.whl

CMD ["bash"]