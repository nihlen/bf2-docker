# bf2-docker

Dockerized Battlefield 2 server based on [insanity54/bf42-dock](https://github.com/insanity54/bf42-dock), with the retail server or with [OpenBF2](https://github.com/B2BF/OpenBF2). The base image is `debian:bullseye-slim` for the retail server and `debian:trixie-slim` for OpenBF2, and was tested on Linux containers in Windows 10 WSL2 and Debian 11. Uses multi-stage builds to keep the image sizes down.

## Prerequisites

- [Docker](https://docker.com/)
- [Docker Compose](https://docs.docker.com/compose/) (optional)

## Usage

Different server variations are placed in the [images](https://github.com/nihlen/bf2-docker/tree/master/images) folder, each complete in its own folder. To create your own, you can copy one of the existing images to use as a base, and then place your custom files in the assets/build/bf2 folder to overwrite any existing files.

The first three images run the retail server and keep their server files and settings in volumes, as described next. The OpenBF2 images work differently, see [The OpenBF2 images](#the-openbf2-images).

Initial settings or passwords can be set using environment variables. Persisted files like settings, logs and demos are put in the `/volume` directory in the container using symbolic links and should be mapped to a host directory. If you want to have full visibility of the server files you can also map the `/home/bf2/srv` folder of the container.

To use these images on a remote host like a VPS you can either use the snippets below to build and run or you can build the images locally and then push them to a container registry like Docker Hub or Azure Container Registry (public or private).

Running multiple servers on the same host can be done by changing the ports in the environment variables and the mapped host port. For this use case I prefer using Docker Compose, an example is listed further down.

### [default](https://github.com/nihlen/bf2-docker/tree/master/images/default)

- Battlefield 2 server (1.5.3153.0)

The basic image to run a Battlefield 2 server. It runs as a LAN server, since the stock server aborts in internet mode without GameSpy (use one of the BF2Hub images to play online), but it can be used as a base. Set `ENV_INTERNET=1` to start it in internet mode anyway.

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

### [openbf2](https://github.com/nihlen/bf2-docker/tree/master/images/openbf2)

- [OpenBF2](https://github.com/B2BF/OpenBF2) server, an open source implementation of the Battlefield 2 server
- BF2Hub ([OpenBF2-BF2Hub](https://github.com/B2BF/OpenBF2-BF2Hub))
- Automatic demo hosting (nginx)

The stock server files with the server binaries replaced by OpenBF2 and its BF2Hub module, to play online. It has no PunkBuster (OpenBF2 has none) and no ModManager, and runs the stock admin script (`sv.adminScript "default"`) with its RCON on port 4711. The RCON password is set using environment variable `ENV_RCON_PASSWORD`; without it nobody can log in. The base image is `debian:trixie-slim`, since OpenBF2 needs a newer glibc.

OpenBF2 publishes no binaries. These are a build of [nihlen/OpenBF2](https://github.com/nihlen/OpenBF2), a fork with the server extension interface and two TV missile settings that are off by default, taken from the release zip of [openbf2-server-ext](https://github.com/nihlen/openbf2-server-ext/releases). BF2Hub's GameSpy domain is compiled into them, so the server reports to BF2Hub's master server. Set `ENV_INTERNET=0` for a LAN server.

```
docker build -t nihlen/bf2-docker/openbf2 https://github.com/nihlen/bf2-docker.git#master:images/openbf2
docker run --name bf2server -v <host directory>:/volume -e ENV_SERVER_NAME='bf2-docker' -e ENV_RCON_PASSWORD='rconpw123' -e ENV_DEMOS_URL='http://www.example.com:80/' -p 80:80/tcp -p 4711:4711/tcp -p 16567:16567/udp -p 29900:29900/udp nihlen/bf2-docker/openbf2:latest
```

### [openbf2-serverext](https://github.com/nihlen/bf2-docker/tree/master/images/openbf2-serverext)

- Server extension ([openbf2-server-ext](https://github.com/nihlen/openbf2-server-ext)), the admin channel to [BF2WebAdmin](https://github.com/nihlen/BF2WebAdmin)

The openbf2 image, including its RCON, with one more OpenBF2 module, `libserverext.so`. BF2WebAdmin (branch `admin-channel`) kicks, bans and runs console commands over its admin channel, and bans stay in the server's own `banlist.con`. Set the four `ENV_ADMIN_*` variables below to connect it; without them the module dials nowhere.

```
docker build -t nihlen/bf2-docker/openbf2-serverext https://github.com/nihlen/bf2-docker.git#master:images/openbf2-serverext
docker run --name bf2server -v <host directory>:/volume -e ENV_SERVER_NAME='bf2-docker' -e ENV_DEMOS_URL='http://www.example.com:80/' -e ENV_ADMIN_CONNECT='bf2wa.example.com:4300' -e ENV_ADMIN_SERVER_ID='203.0.113.10:16567' -e ENV_ADMIN_KEY='<hex key from BF2WebAdmin>' -e ENV_ADMIN_CERT_SHA256='<pin of BF2WebAdmin's certificate>' -p 80:80/tcp -p 16567:16567/udp -p 29900:29900/udp nihlen/bf2-docker/openbf2-serverext:latest
```

### The OpenBF2 images

This applies to `openbf2`, `openbf2-serverext` and the `netsky-openbf2-*` images. Their `Dockerfile`, `build.sh`, `setup.sh` and `run.sh` are the same files in every folder. What an image is comes from its data: `assets/build/bf2/` (the settings, `mods/bf2/openbf2.con` and admin scripts), `maps.txt` and `levels/`.

**Modules.** `mods/bf2/openbf2.con` loads the modules before Python starts (`openbf2.addModDll "bf2hub"`, and `"serverext"` in the images with the server extension), so the server runs `start.sh` instead of `start_bf2hub.sh`. A module that an image's `openbf2.con` does not load is left out of the image.

**Settings on every start.** The server files are part of the image and are not copied to a volume. `run.sh` renders the settings from templates (`/home/bf2/templates`) and the environment variables on every start, so a new image or a changed variable takes effect when the container is recreated. Don't edit settings in the container.

| Variable | Default | |
|---|---|---|
| `ENV_SERVER_NAME` | `bf2-docker` | `sv.serverName` |
| `ENV_MAX_PLAYERS` | `16` | `sv.maxPlayers` |
| `ENV_SERVER_PORT` | `16567` | `sv.serverPort`, the game port (udp) |
| `ENV_GAMESPY_PORT` | `29900` | `sv.gameSpyPort`, the query port (udp) |
| `ENV_INTERNET` | `1` | `sv.internet`, 0 for a LAN server that is not listed on the master server |
| `ENV_DEMOS_URL` | `http://example.com/demos/` | `sv.demoIndexURL` and `sv.demoDownloadURL` |
| `ENV_CONTENT_CHECK` | `1` | 0 turns off the content check, see below |
| `ENV_RCON_PASSWORD` | none | The password of the stock admin script's RCON: 4711/tcp in the container, and `rcon login <password>` in the game's console. Printable characters without spaces or `=`. Without it the port is open but nobody can log in. Only in an image that runs the stock admin script (`openbf2`, `openbf2-serverext`); with another admin script, like the netsky images', there is no RCON and the variable is ignored |
| `ENV_TV_AIM_FROM_MISSILE` | `0` (off, retail) | OpenBF2 `vars.set tv-aim-from-missile`, metres: a TV missile's aim point that would make it stop turning (a wall beside it) is cast again from the server's missile when the client's camera is at most this far from it |
| `ENV_TV_TURN_BEHIND` | `0` (off, retail) | OpenBF2 `vars.set tv-turn-behind`, 1: a TV missile keeps turning towards an aim point beside or behind it instead of flying straight |
| `ENV_SPONSOR_VARS` | none (the netsky images have their own) | [sponsortext](https://github.com/cetteup/sponsortext) variables, added as ` $vars:<value>$` at `{{sponsor_vars}}` in the template's `sv.sponsorText`, which server browsers read from the GameSpy query. `key=value` pairs separated by `;` (escape `=`, `;`, `$` and `\` in a value with `\`); no double quotes. Set but empty: no variables. An image sets its own default with a line `rem default ENV_SPONSOR_VARS=<value>` in its `serversettings.con` |

Only with the server extension (`openbf2-serverext`, `netsky-openbf2-*`):

| Variable | Default | |
|---|---|---|
| `ENV_ADMIN_CONNECT` | none | BF2WebAdmin's admin channel listener, `<host>:<port>` (e.g. `bf2wa.nihlen.net:4300`). The module dials it over TLS |
| `ENV_ADMIN_SERVER_ID` | none | The server's id in BF2WebAdmin (`Server.ServerId`, e.g. `<public ip>:<game port>`) |
| `ENV_ADMIN_KEY` | none | The server's admin key in BF2WebAdmin (`Server.AdminKey`), 32 to 128 hex digits |
| `ENV_ADMIN_CERT_SHA256` | none | The pin of BF2WebAdmin's certificate, 64 hex digits (`BF2WebAdmin.Server --admin-pin`, or the `adminCertSha256` line of `--admin-cert-create`) |
| `ENV_BOT_PORT` | `16700` | The module's bot channel, always on `127.0.0.1` inside the container. It has no authentication, never publish it |

Set all four `ENV_ADMIN_*` variables or none. Without them the module dials nowhere (the log says `admin channel: off`), and `run.sh` refuses to start with only some of them, or with any of them in an image without the module. The module's other settings are fixed in the rendered `serverext.cfg`: `stepMode 0`, `allowTeleport 0`, `allowRoundRestart 0`, `adminAllowConsole 1`.

**Other settings and the map list.** The variables cover what differs between servers. For anything else, without building an image, put your own `serversettings.con` or `maplist.con` in `/volume/templates/`: `run.sh` uses it instead of the image's template and renders it the same way. Start from the image's file (`assets/build/bf2/mods/bf2/settings/serversettings.con`, or `/home/bf2/templates/mods/bf2/settings/` in the container) and keep the `{{...}}` placeholders you want to set with variables. `run.sh` only reads this folder. Custom maps still need an image, see [Custom maps](#custom-maps).

**Content check.** With the four fingerprint files in `mods/bf2` (`std_archive.md5`, `std_archive_mod.md5`, `bst_archive.md5`, `bst_archive_mod.md5`) the server compares the checksums a client reports of its game files and kicks a client with modified files. `ENV_CONTENT_CHECK=0` removes them, for a server where players may use modified game files (a "nocheck" server). The check is not anti-cheat: the client computes the checksums itself. On a map without an `archive.md5` in its folder the server compares only four small `.con` files and not the game archives. That is every custom map, since the build leaves a map's `archive.md5` out unless it is in `levels/<map>/`.

**What persists.** Only `/volume`, mounted from the host or a named volume. `/home/bf2/srv` must not be mounted (a volume there would keep the server files of an older image), `run.sh` refuses to start if it is.

| Path | |
|---|---|
| `/volume/settings/banlist.con` | BF2's ban list |
| `/volume/demos/pending`, `/volume/demos/uploaded` | Demos being recorded, and the finished ones nginx serves at `/demos/` (`rotate_demo.py` keeps 50) |
| `/volume/bf2.log` | The server console of this start, `bf2.log.1` of the previous start |
| `/volume/logs` | Module logs (`logs/bf2hub`) |
| `/volume/templates` | Optional, yours: templates used instead of the image's (above) |

The rendered settings are not in `/volume`. A `/volume` from a retail image keeps its previous copies of `maplist.con`, `modmanager.con` and `serversettings.con` as `<file>.old`. `mm_bans.xml` and `modmanager.log` from an image with ModManager are not used and can be deleted. The module's own log lines go to `docker logs`.

```yaml
services:
  bf2-openbf2:
    container_name: bf2-openbf2
    image: nihlen/bf2-docker/openbf2-serverext
    # BF2WebAdmin's .restartserver quits the server with exit code 0, which on-failure would not restart
    restart: unless-stopped
    environment:
      - ENV_SERVER_NAME=bf2-docker #1
      - ENV_MAX_PLAYERS=16
      - ENV_SERVER_PORT=16567
      - ENV_GAMESPY_PORT=29900
      - ENV_DEMOS_URL=http://www.example.com:8000/
      - ENV_ADMIN_CONNECT=bf2wa.example.com:4300
      - ENV_ADMIN_SERVER_ID=203.0.113.10:16567
      - ENV_ADMIN_KEY=<hex key from BF2WebAdmin>
      - ENV_ADMIN_CERT_SHA256=<pin of BF2WebAdmin's certificate>
    volumes:
      - "/data/bf2/bf2-openbf2/volume:/volume"
    ports:
      - "8000:80/tcp"
      - "16567:16567/udp"
      - "29900:29900/udp"
```

**The OpenBF2 release.** The binaries come from one zip, `openbf2-serverext-<openbf2>-<module>-<bf2hub>-bf2hub.zip` (the three commits), a [release of openbf2-server-ext](https://github.com/nihlen/openbf2-server-ext/releases) that is unpacked into `bin/amd-64`. Its `source.txt` is `/home/bf2/srv/openbf2-source.txt` in the image. To move to a new release, change the zip's URL in `assets/build/assets.txt` and its line in `assets/build/assets.sha512` (the release's `.zip.sha512` file is that line) in every OpenBF2 image. `build.sh` takes the zip's name from `assets.txt`.

### netsky-openbf2-*

- [netsky-openbf2-2v2](https://github.com/nihlen/bf2-docker/tree/master/images/netsky-openbf2-2v2): 2v2 chopper server
- [netsky-openbf2-chopper-mayhem](https://github.com/nihlen/bf2-docker/tree/master/images/netsky-openbf2-chopper-mayhem): Chopper mayhem on Dalian Plant
- [netsky-openbf2-dogfight](https://github.com/nihlen/bf2-docker/tree/master/images/netsky-openbf2-dogfight): Dogfight server
- [netsky-openbf2-inf](https://github.com/nihlen/bf2-docker/tree/master/images/netsky-openbf2-inf): Infantry server, a placeholder with its settings and no image yet

Images used for the NeTskY servers, and an example of making your own: each is `openbf2-serverext` with its own data and nothing else.

- `serversettings.con` and `maplist.con`, with a description per server type in `sv.sponsorText` and the servers' own `ENV_SPONSOR_VARS` default (`website=https://bf2.nihlen.net/;discord=https://discord.gg/DPaJaMKAc3;provider=bf2hub.com`).
- The admin script `admin/netsky.py` (`sv.adminScript "netsky"`), a port of the one ModManager module the servers used, `mm_autobalance` as it was configured (`roundSwitch 1`, no commander or squad balancing): a connecting player joins the team with fewer players, every player swaps teams at the end of a round, and with `sv.autoBalanceTeam 1` (off in these images) dying players and team changes are balanced. It writes `netsky: admin script loaded` to the server console when it starts.
- Custom maps (`maps.txt`) and changes to maps (`levels/`), see [Custom maps](#custom-maps).

The 2v2 server without the content check ("nocheck") is `netsky-openbf2-2v2` with `ENV_CONTENT_CHECK=0`. The retail netsky images (`netsky-2v2`, `netsky-2v2-nocheck`, `netsky-chopper-mayhem`, `netsky-dogfight`, `netsky-inf`) and `bf2hub-pb-mm-webadmin`, which they were based on, have been removed. They needed `mm_webadmin.py`, which BF2WebAdmin no longer supports.

### Custom maps

Custom maps are downloaded during the build of an OpenBF2 image. List the map archive URLs in `assets/build/maps.txt` and their checksums in `assets/build/maps.sha512`. Each archive should contain a single map folder, like the ones on [static.nihlen.net/bf2/maps](https://static.nihlen.net/bf2/maps/). Only the server files are extracted, `client.zip` and `archive.md5` are skipped.

Server-side changes to a map are placed in `assets/build/levels/<map>`. Files in `levels/<map>/server.zip/` are updated inside the map's server.zip, so you only need to commit the changed files (e.g. `levels/dalian_2_v_2/server.zip/GameModes/gpm_cq/16/GamePlayObjects.con`). Other files, like `archive.md5`, are copied to the map folder as-is.

### Docker Compose

To simplify setting up multiple servers on the same host you can use Docker Compose. The `image:` property can point to a locally built image or a URL to your container registry of choice. Note that the game server port and gamespy port need to match in the environment variables and in the Docker port configuration.

Here is an example of running two retail servers on the same host (the OpenBF2 images have their own example above):

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

Test your changes with `tests/run.sh static` and `tests/run.sh build <image>`, see [tests](tests/README.md). The image folders are copies of each other on purpose, so a change to a file that an image family shares has to be made in every folder of the family: the static checks fail if the OpenBF2 images' shared files differ. [CLAUDE.md](CLAUDE.md) lists the families and the steps for common changes.

The [CI workflow](.github/workflows/ci.yml) runs the static checks on every push and pull request. Images with changes in `images/<image>/` are built and smoke tested (all images if `tests/` or `.github/` changed). A folder without a `Dockerfile` is not an image. Tested images are pushed to `cr.nihlen.net/library/bf2-docker:<image>`, overwriting the previous image. Images are only pushed from the branches in the `PUSH_BRANCHES` repository variable (default `master`), using the `CR_USERNAME` and `CR_PASSWORD` secrets. Since the image layers are larger than Cloudflare's 100 MB upload limit, the job joins the tailnet as `tag:ci` (a Tailscale federated identity credential in the `TS_OAUTH_CLIENT_ID` and `TS_AUDIENCE` secrets) and pushes to the same registry through its tailnet-only hostname `cr-ts.nihlen.net`. On the default branch it can also be run manually for selected images under Actions > CI > Run workflow.

Contributions to new or existing images are welcome if you want them public.
