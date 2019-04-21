# bf2-docker

Dockerized Battlefield 2. Based on [insanity54/bf42-dock](https://github.com/insanity54/bf42-dock) by Chris Grimmett. It uses `debian:stretch-slim` as base image and has been tested on both Windows and Linux hosts.

## Prerequisites

* [Docker](https://docker.com/)

## Usage

You can build different versions depending on what you need. These versions are located in separate branches and can be built using `#<branch name>` after the GitHub URL.

### [Default](https://github.com/nihlen/bf2-docker)

 * Battlefield 2 server (1.5.3153.0)
 * BF2Hub Unranked (R3)

The basic image to run a Battlefield 2 server online using the BF2Hub service.

```
docker build -t nihlen/bf2-docker https://github.com/nihlen/bf2-docker.git
docker run --name bf2server -v <host directory>:/home/bf2/srv -p 4711:4711/tcp -p 4712:4712/tcp -p 16567:16567/udp -p 27901:27901/udp -p 29900:29900/udp nihlen/bf2-docker:latest
```

### [Enhanced](https://github.com/nihlen/bf2-docker/tree/enhanced)

 * ModManager (2.2c)
 * Automatic demo hosting
 
Various enhancements will go in this version. If you want to persist the demos on the host you can use `-v <host directory>:/var/www/html/demos`.

```
docker build -t nihlen/bf2-docker/enhanced https://github.com/nihlen/bf2-docker.git#enhanced
docker run --name bf2server -v <host directory>:/home/bf2/srv -p 80:80/tcp -p 4711:4711/tcp -p 4712:4712/tcp -p 16567:16567/udp -p 27901:27901/udp -p 29900:29900/udp nihlen/bf2-docker/enhanced:latest
```

### [BF2CC](https://github.com/nihlen/bf2-docker/tree/enhanced-bf2cc)

 * BF2CC Daemon (1.4.2446)

Runs with bf2ccd.exe using Mono. The RCON and BF2CC Daemon passwords are generated and printed in the console when creating the container. So it's recommended to run in interactive mode (-it) the first time.

```
docker build -t nihlen/bf2-docker/enhanced-bf2cc https://github.com/nihlen/bf2-docker.git#enhanced-bf2cc
docker run --name bf2server -it -v <host directory>:/home/bf2/srv -p 80:80/tcp -p 4711:4711/tcp -p 4712:4712/tcp -p 16567:16567/udp -p 27901:27901/udp -p 29900:29900/udp nihlen/bf2-docker/enhanced-bf2cc:latest
```

## Development

Download the [assets](assets/assets.txt) and put them in the assets/ folder so you don't need to redownload them on each build. Then make your changes in Dockerfile, setup.sh or start.sh, build and run with `.\build.bat`. Make sure Docker is set to use Linux containers.

## Future improvements

* Docker compose
* Shared volume, but different settings (symlink?)
* Shared nginx container
