FROM debian:stretch-slim
LABEL maintainer=nihlen

# Environment variables
ENV SERVER_NAME="bf2-docker"

# Get required packages and create our user
RUN apt -y update && \
    apt-get -y update && \
    apt-get -y install wget expect libncurses5 dos2unix && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    useradd --create-home --shell /bin/bash bf2

# Add assets to image
WORKDIR /home/bf2/tmp
COPY ./assets ./

# For Windows hosts con
RUN find . -type f -exec dos2unix -k -s -o {} ';' && apt-get --purge remove -y dos2unix

# Extract server files
RUN bash -x ./setup.sh

# Move server files to persisted folder and start server
CMD ./start.sh
