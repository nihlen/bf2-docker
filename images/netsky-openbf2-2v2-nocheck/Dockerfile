# Build stage
FROM debian:trixie-slim AS build

# Add assets to image
WORKDIR /home/bf2/tmp
COPY ./assets/build ./

# Download and extract server files
RUN bash -x ./build.sh

# Runtime stage
FROM debian:trixie-slim AS runtime
WORKDIR /home/bf2/tmp
LABEL maintainer=nihlen

# Environment variables
ENV SERVER_NAME="bf2-docker"

# Copy runtime assets
COPY ./assets/runtime ./

# Install required packages and set permissions
RUN bash -x ./setup.sh

# The server runs from the image, only /volume persists (see run.sh)
COPY --from=build --chown=bf2:bf2 /home/bf2/tmp/srv /home/bf2/srv
COPY --from=build --chown=bf2:bf2 /home/bf2/tmp/templates /home/bf2/templates
WORKDIR /home/bf2

# Render the settings from the environment and start the server
CMD ["./run.sh"]
