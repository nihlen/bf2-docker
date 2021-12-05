# Build stage
FROM debian:stretch-slim AS build

# Add assets to image
WORKDIR /home/bf2/tmp
COPY ./assets/build ./

# Download and extract server files
RUN bash -x ./build.sh

# Runtime stage
FROM debian:stretch-slim AS runtime
WORKDIR /home/bf2/tmp
LABEL maintainer=nihlen

# Environment variables
ENV SERVER_NAME="bf2-docker"

# Copy runtime assets
COPY ./assets/runtime ./

# Install required packages and set permissions
RUN bash -x ./setup.sh

# Copy server files from the build stage
COPY --from=build /home/bf2/tmp/srv ./srv

# Move server files to persisted folder and start server
CMD ./run.sh
