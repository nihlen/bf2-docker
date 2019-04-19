FROM debian:stretch-slim
LABEL maintainer=nihlen

# Environment variables
ENV SERVER_NAME="bf2-docker"

# Get required packages and create our user
RUN dpkg --add-architecture i386 && \
    apt -y update && \
    apt-get -y update && \
    apt-get -y install wget expect libncurses5 nginx unzip python libglib2.0-0:i386 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    useradd --create-home --shell /bin/bash bf2

# Add assets to image
WORKDIR /home/bf2/tmp
COPY ./assets ./

# Extract server files
RUN bash -x ./setup.sh

# Move server files to persisted folder and start server
CMD ./start.sh
