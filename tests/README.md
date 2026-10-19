# Tests

Run from the repository root with bash (Git Bash on Windows). Requires Docker and Python 3.

```sh
tests/run.sh static                    # all images
tests/run.sh build netsky-2v2          # one or more images
tests/run.sh all
```

The script exits with a non-zero code if any test fails.

## static

Fast checks without building anything:

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
tests/run.sh build --keep netsky-dogfight
```

## Tools

[compare-levels.py](tools/compare-levels.py) compares two levels folders, e.g. the maps of a running server with a new build. Zip files are compared entry by entry.

```sh
python tests/tools/compare-levels.py /data/bf2/server/mods/bf2/levels tests/out/netsky-dogfight/levels
python tests/tools/compare-levels.py <reference> <levels> idf_arena idf_gulf   # only some maps
```
