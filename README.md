# bf2-docker

Dockerized Battlefield 2 server based on [insanity54/bf42-dock](https://github.com/insanity54/bf42-dock). The base image is `debian:bullseye-slim` and was tested on Linux containers in Windows 10 WSL2 and Debian 11. Uses multi-stage builds to keep the image sizes down.

## Prerequisites

- [Docker](https://docker.com/)
- [Docker Compose](https://docs.docker.com/compose/) (optional)

## Usage

Different server variations are placed in the [images](https://github.com/nihlen/bf2-docker/tree/master/images) folder. To create your own, you can copy one of the existing images to use as a base, and then place your custom files in the assets/bf2 folder to overwrite any existing files.

Initial settings or passwords can be set using environment variables. Persisted files like settings, logs and demos are put in the `/volume` directory in the container using symbolic links and should be mapped to a host directory. If you want to have full visibility of the server files you can also map the `/home/bf2/srv` folder of the container.

To use these images on a remote host like a VPS you can either use the snippets below to build and run or you can build the images locally and then push them to a container registry like Docker Hub or Azure Container Registry (public or private).

Running multiple servers on the same host can be done by changing the ports in the environment variables and the mapped host port. For this use case I prefer using Docker Compose, an example is listed further down.

### [default](https://github.com/nihlen/bf2-docker/tree/master/images/default)

- Battlefield 2 server (1.5.3153.0)

The basic image to run a Battlefield 2 server. Not practical since you can't play online but it can be used as a base.

```
docker build -t nihlen/bf2-docker/default https://github.com/nihlen/bf2-docker.git#master:images/default
docker run --name bf2server -v <host directory>:/volume -p 4711:4711/tcp -p 4712:4712/tcp -p 16567:16567/udp -p 27901:27901/udp -p 29900:29900/udp nihlen/bf2-docker/default:latest
```

### [bf2hub-pb-mm](https://github.com/nihlen/bf2-docker/tree/master/images/bf2hub-pb-mm)

- BF2Hub Unranked (R3)
- Updated PunkBuster
- ModManager (2.2c)
- Automatic demo hosting (nginx)

Uses BF2Hub to play online. The RCON password is set using environment variable `ENV_RCON_PASSWORD`. If you want to persist the demos on the host you can use `-v <host directory>:/var/www/html/demos` and use `-e ENV_DEMOS_URL='<host address>'` to provide demo urls after finished rounds.

```
docker build -t nihlen/bf2-docker/bf2hub-pb-mm https://github.com/nihlen/bf2-docker.git#master:images/bf2hub-pb-mm
docker run --name bf2server -v <host directory>:/volume -e ENV_RCON_PASSWORD='rconpw123' -e ENV_DEMOS_URL='http://www.example.com:80/' -p 80:80/tcp -p 4711:4711/tcp -p 4712:4712/tcp -p 16567:16567/udp -p 27901:27901/udp -p 29900:29900/udp nihlen/bf2-docker/bf2hub-pb-mm:latest
```

### [bf2hub-pb-mm-bf2cc](https://github.com/nihlen/bf2-docker/tree/master/images/bf2hub-pb-mm-bf2cc)

- BF2CC Daemon (1.4.2446)

Runs with bf2ccd.exe using Mono. The RCON and BF2CC Daemon passwords are set using environment variables `ENV_RCON_PASSWORD` and `ENV_BF2CCD_PASSWORD`.

```
docker build -t nihlen/bf2-docker/bf2hub-pb-mm-bf2cc https://github.com/nihlen/bf2-docker.git#master:images/bf2hub-pb-mm-bf2cc
docker run --name bf2server -it -v <host directory>:/volume -e ENV_RCON_PASSWORD='rconpw123' -e ENV_BF2CCD_PASSWORD='bf2ccdpw123' -e ENV_DEMOS_URL='http://www.example.com:80/' -p 80:80/tcp -p 4711:4711/tcp -p 4712:4712/tcp -p 16567:16567/udp -p 27901:27901/udp -p 29900:29900/udp nihlen/bf2-docker/bf2hub-pb-mm-bf2cc:latest
```

### netsky-*

- [netsky-2v2](https://github.com/nihlen/bf2-docker/tree/master/images/netsky-2v2): 2v2 chopper server
- [netsky-2v2-nocheck](https://github.com/nihlen/bf2-docker/tree/master/images/netsky-2v2-nocheck): 2v2 chopper server without PunkBuster and MD5 checks
- [netsky-openbf2-2v2-nocheck](https://github.com/nihlen/bf2-docker/tree/master/images/netsky-openbf2-2v2-nocheck): netsky-2v2-nocheck with the server binaries replaced by OpenBF2, an open source implementation. Uses `debian:trixie-slim` since OpenBF2 needs a newer glibc. OpenBF2 loads its own BF2Hub module from `mods/bf2/openbf2.con` (`openbf2.addModDll "bf2hub"`) instead of `start_bf2hub.sh`.
- [netsky-chopper-mayhem](https://github.com/nihlen/bf2-docker/tree/master/images/netsky-chopper-mayhem): Chopper mayhem on Dalian Plant
- [netsky-dogfight](https://github.com/nihlen/bf2-docker/tree/master/images/netsky-dogfight): Dogfight server
- [netsky-inf](https://github.com/nihlen/bf2-docker/tree/master/images/netsky-inf): Infantry server

Images used for the NeTskY servers. Based on bf2hub-pb-mm-webadmin with custom settings and maps.

### Custom maps

Custom maps are downloaded during the build. List the map archive URLs in `assets/build/maps.txt` and their checksums in `assets/build/maps.sha512`. Each archive should contain a single map folder, like the ones on [static.nihlen.net/bf2/maps](https://static.nihlen.net/bf2/maps/). Only the server files are extracted, `client.zip` and `archive.md5` are skipped.

Server-side changes to a map are placed in `assets/build/levels/<map>`. Files in `levels/<map>/server.zip/` are updated inside the map's server.zip, so you only need to commit the changed files (e.g. `levels/dalian_2_v_2/server.zip/GameModes/gpm_cq/16/GamePlayObjects.con`). Other files, like `archive.md5`, are copied to the map folder as-is.

### Docker Compose

To simplify setting up multiple servers on the same host you can use Docker Compose. The `image:` property can point to a locally built image or a URL to your container registry of choice. Note that the game server port and gamespy port need to match in the environment variables and in the Docker port configuration.

Here is an example of running two servers on the same host:

```yaml
version: "3.3"
services:
  bf2-docker-1-service:
    container_name: bf2-docker-1
    image: nihlen/bf2-docker/bf2hub-pb-mm
    restart: on-failure
    environment:
      - ENV_SERVER_NAME=bf2-docker #1
      - ENV_MAX_PLAYERS=16
      - ENV_SERVER_PORT=16567
      - ENV_GAMESPY_PORT=29900
      - ENV_DEMOS_URL=http://www.example.com:8000/
      - ENV_RCON_PASSWORD=rconpw123
    volumes:
      - "/data/bf2/bf2-docker-1/server:/home/bf2/srv"
      - "/data/bf2/bf2-docker-1/volume:/volume"
    ports:
      - "8000:80/tcp"
      - "4711:4711/tcp"
      - "4712:4712/tcp"
      - "16567:16567/udp"
      - "27901:27901/udp"
      - "29900:29900/udp"

  bf2-docker-2-service:
    container_name: bf2-docker-2
    image: nihlen/bf2-docker/bf2hub-pb-mm-bf2cc
    restart: on-failure
    environment:
      - ENV_SERVER_NAME=bf2-docker #2
      - ENV_MAX_PLAYERS=4
      - ENV_SERVER_PORT=16569
      - ENV_GAMESPY_PORT=29901
      - ENV_DEMOS_URL=http://www.example.com:8001/
      - ENV_RCON_PASSWORD=rconpw123
      - ENV_BF2CCD_PASSWORD=bf2ccdpw123
    volumes:
      - "/data/bf2/bf2-docker-2/server:/home/bf2/srv"
      - "/data/bf2/bf2-docker-2/volume:/volume"
    ports:
      - "8001:80/tcp"
      - "4721:4711/tcp"
      - "4722:4712/tcp"
      - "16569:16569/udp"
      - "27911:27901/udp"
      - "29901:29901/udp"
```

Place the docker-compose.yml on the host and run `docker-compose up -d --remove-orphans` to create the containers. If you are not using a container registry then the images need to be built on the host first.

## Development

First set up Docker Desktop on Windows (WSL2).

Download the assets (see assets.txt) and put them in the images/\*/assets/build/ folder so you don't need to redownload them on each build. Maps (see maps.txt) go in the images/\*/assets/build/maps/ folder. Then make your changes in Dockerfile, build.sh, setup.sh and run.sh. Build and run with `.\build.bat`. Make sure Docker is set to use Linux containers.

Test your changes with `tests/run.sh static` and `tests/run.sh build <image>`, see [tests](tests/README.md).

The [CI workflow](.github/workflows/ci.yml) runs the static checks on every push and pull request. Images with changes in `images/<image>/` are built and smoke tested (all images if `tests/` or `.github/` changed). Tested images are pushed to `cr.nihlen.net/library/bf2-netsky:<name>` (`images/netsky-<name>`) or `cr.nihlen.net/library/bf2-docker:<image>`, overwriting the previous image. Images are only pushed from the branches in the `PUSH_BRANCHES` repository variable (default `master`), using the `CR_USERNAME` and `CR_PASSWORD` secrets. Since the image layers are larger than Cloudflare's 100 MB upload limit, the job joins the tailnet as `tag:ci` (a Tailscale federated identity credential in the `TS_OAUTH_CLIENT_ID` and `TS_AUDIENCE` secrets) and pushes to the same registry through its tailnet-only hostname `cr-ts.nihlen.net`. On the default branch it can also be run manually for selected images under Actions > CI > Run workflow.

Contributions to new or existing images are welcome if you want them public.
