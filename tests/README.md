# Tests

Run from the repository root with bash (Git Bash on Windows). Requires Docker and Python 3.

```sh
tests/run.sh static                    # all images
tests/run.sh build openbf2             # one or more images
tests/run.sh smoke openbf2             # start the image and check that it works
tests/run.sh all
```

The script exits with a non-zero code if any test fails. An image is a folder in `images/` with a `Dockerfile`.

## static

Fast checks without building anything:

- The files that the images of a family share are the same in every folder of the family, e.g. `build.sh`, `run.sh` and the pinned OpenBF2 release in all OpenBF2 images (`FAMILIES` in [check.py](static/check.py)). This is checked for all images, whichever were asked for.
- Every file in `assets.txt` and `maps.txt` has a checksum in `assets.sha512` and `maps.sha512`, and the other way round.
- Every map in `maplist.con` is a stock map ([stock-maps.txt](stock-maps.txt)) or downloaded in `maps.txt`. Map archives are matched by name without a leading `#`, e.g. `#1_sharqi_2v2` is `1_sharqi_2v2.zip`.
- Every `levels/<map>` folder belongs to a stock or downloaded map, and `levels/<map>/server.zip` is a non-empty folder.
- [ShellCheck](https://www.shellcheck.net/) finds no warnings or errors in `build.sh`, `setup.sh` and `run.sh` ([.shellcheckrc](.shellcheckrc) lists the ignored ones).

## build

Builds each image (all stages) and checks the server files inside it:

- Every map in the server's `maplist.con` has a folder with a `server.zip`.
- No `server.zip` is corrupt or has duplicate entries, no map folder has a `client.zip` or an `Info` folder.
- Every file in `levels/<map>` ended up in the built map, byte for byte.

Put the downloaded assets and maps in the image folders (see the main README) to avoid downloading them on every build. Use `--keep` to save the built maps to `tests/out/<image>/levels`:

```sh
tests/run.sh build --keep netsky-openbf2-dogfight
```

## smoke

Starts each image (building it first if needed) with test passwords and checks that it works, depending on what the image contains:

- The `bf2` process starts and the game port (16567/udp) is open.
- OpenBF2 loads every module listed in `mods/bf2/openbf2.con` (checked on the server console).
- An admin script of the image's own (`sv.adminScript`, `admin/<name>.py`, e.g. `netsky.py`) writes `<name>: admin script loaded` on the server console, and the console has no admin script errors.
- With ModManager: RCON accepts a login, the server name is set from `ENV_SERVER_NAME`, and all maps in `maplist.con` and modules in `modmanager.con` are loaded.
- OpenBF2: with an admin script of the image's own, nothing listens on the RCON port; with the stock admin script, RCON accepts a login with `ENV_RCON_PASSWORD` and runs a console command. The GameSpy query (29900/udp) reports the server name from `ENV_SERVER_NAME`, the image's sponsortext variables in `sv.sponsorText` (none in an image without a default), the content check (`bf2_pure`) and the first map in `maplist.con`.
- nginx serves the demo list at `/demos/`.
- The demo hook runs like the server runs it after a round, and the demo is then listed and downloadable.
- The container keeps running.
- OpenBF2, in a second container that is not waited for: `ENV_CONTENT_CHECK=0` removes the fingerprint files, no RCON password file is written without `ENV_RCON_PASSWORD`, and a `serversettings.con` in `/volume/templates` is used and rendered. In an image without the server extension, `run.sh` refuses the `ENV_ADMIN_*` variables.

The container ports are published on random localhost ports, so the tests don't conflict with running servers. On failure the end of the container log is printed.

## Tools

[compare-levels.py](tools/compare-levels.py) compares two levels folders, e.g. the maps of a running server with a new build. Zip files are compared entry by entry.

```sh
python tests/tools/compare-levels.py /data/bf2/server/mods/bf2/levels tests/out/netsky-openbf2-dogfight/levels
python tests/tools/compare-levels.py <reference> <levels> idf_arena idf_gulf   # only some maps
```

[repack-map.py](tools/repack-map.py) repacks a downloaded map archive for a map server: one lowercase top folder,
`info/<name>.desc` named after it, and entries removed from `server.zip` if given. Other files are copied byte for byte.

```sh
python -I tests/tools/repack-map.py DF_BLACKHOLE8.zip df_blackhole8.zip df_blackhole8 map.desc
```
