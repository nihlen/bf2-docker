# bf2-docker

Docker images of Battlefield 2 servers. [README.md](README.md) is the user documentation, [tests/README.md](tests/README.md)
describes the tests.

## Layout

Every folder in `images/` with a `Dockerfile` is one image, complete in its own folder. A folder without a `Dockerfile`
is not an image (`netsky-openbf2-inf` is a placeholder with notes).

```
images/<image>/Dockerfile
images/<image>/assets/build/     build stage: build.sh, extract, assets.txt + assets.sha512 (downloads),
                                 bf2/ (files copied over the server's), maps.txt + maps.sha512, levels/ (map changes)
images/<image>/assets/runtime/   runtime stage: setup.sh (image setup), run.sh (container start), nginx/
```

**The folders are copies of each other on purpose.** There is no shared base image and no shared script folder:
`docker build <repo>#<branch>:images/<image>` must work on its own, and an image folder must be readable without the
rest of the repo. Keep it that way. Don't add a common folder, a base image, symlinks or a generator. The cost is that
a change to a shared file is made in every folder that has it, which is what this file and the static checks are for.

## Image families

| Family | Images | Base |
|---|---|---|
| Retail | `default`, `bf2hub-pb-mm`, `bf2hub-pb-mm-bf2cc` | `debian:bullseye-slim`, apt from `archive.debian.org` |
| OpenBF2 | `openbf2`, `openbf2-serverext`, `netsky-openbf2-2v2`, `netsky-openbf2-chopper-mayhem`, `netsky-openbf2-dogfight` | `debian:trixie-slim` |

### OpenBF2: same scripts, different data

These files are byte-identical in every OpenBF2 image. Change one, then copy it to the others:

```
.dockerignore
Dockerfile
assets/build/assets.sha512
assets/build/assets.txt
assets/build/bf2/adminutils/demo/rotate_demo.py
assets/build/bf2/rotate_demo.cfg
assets/build/build.sh
assets/build/extract
assets/runtime/nginx/default
assets/runtime/run.sh
assets/runtime/setup.sh
```

`assets/build/bf2/admin/netsky.py` is identical in the `netsky-openbf2-*` images.

`tests/static/check.py` (`FAMILIES`) fails when any of these differ. If a new file must be shared, add it there.

An image differs from the others only in its data, and the scripts must not test for an image's name:

- `assets/build/bf2/mods/bf2/openbf2.con` decides the modules. `build.sh` removes `libbf2hub.so` or `libserverext.so`
  when the file does not load it, and `run.sh` sets up the server extension only when `libserverext.so` is there.
  `openbf2` loads `bf2hub`; all the others load `bf2hub` and `serverext`.
- `assets/build/bf2/mods/bf2/settings/serversettings.con` and `maplist.con` are templates with `{{...}}` placeholders
  that `run.sh` fills from `ENV_*` variables on every start. An image without a `maplist.con` uses the stock one. A
  line `rem default ENV_SPONSOR_VARS=<value>` in `serversettings.con` is the image's default for that variable.
- `assets/build/bf2/admin/<name>.py` with `sv.adminScript "<name>"`, `maps.txt` + `maps.sha512`, and `levels/`. The stock
  admin script (`sv.adminScript "default"`, in `openbf2` and `openbf2-serverext`) has an RCON, which `run.sh` gives a
  password from `ENV_RCON_PASSWORD`; an image's own admin script has none.

So `openbf2-serverext` is `openbf2` plus one line in `openbf2.con`, and a `netsky-openbf2-*` image is
`openbf2-serverext` plus settings, a map list, `admin/netsky.py`, maps and map changes. If a netsky image needs
something the scripts can't do from data, add a data-driven feature to the scripts of all OpenBF2 images.

The server files live in the image, and `run.sh` renders the settings on every container start; only `/volume`
persists. Nothing in the image is edited by hand at run time. The retail images work the other way (server files and
settings are moved to volumes on the first start) and are not kept in step with each other beyond what they already
share.

netsky is the name of the repo owner's own servers. Those images are in the repo as they are deployed, and as an
example for others. Keep anything specific to them (names, URLs, maps, the admin script) out of `openbf2` and
`openbf2-serverext`.

## Common changes

**A new OpenBF2 release.** The binaries are one zip from a GitHub release of
[nihlen/openbf2-server-ext](https://github.com/nihlen/openbf2-server-ext/releases). In every OpenBF2 image:

1. `assets/build/assets.txt`: the zip's new URL (second line).
2. `assets/build/assets.sha512`: the zip's line, which is the content of the release's `<zip>.sha512` file.

`build.sh` reads the zip's name from `assets.txt`, nothing else names it. The BF2 installer tgz and the custom maps are
on static.nihlen.net and are not part of a release.

**A new environment variable or start-up behaviour.** Change `run.sh` in one OpenBF2 image, copy it to the others,
add the variable to the table in README.md, and add a check to `tests/smoke/smoke.py` if it can be checked.

**A new image.** Copy the closest image's folder. For a netsky server that is `openbf2-serverext` plus `admin/netsky.py`
from another netsky image. Add it to README.md. CI finds it by its `Dockerfile` and pushes it to
`cr.nihlen.net/library/bf2-docker:<image>`: the tag is the folder's name.

**A custom map or a change to a map.** See "Custom maps" in README.md. A map in `maplist.con` must be a stock map
(`tests/stock-maps.txt`) or in `maps.txt`.

A new custom map from a zip, for a netsky image:

1. Repack it: `python -I tests/tools/repack-map.py <in.zip> <out.zip> <name> [server.zip entries to drop]` makes the
   folder `<name>` (lowercase) and `info/<name>.desc`. Compare it with an existing map first (`info/` holds the
   `.desc` and the pngs, `server.zip`, `client.zip`) and ask the owner about anything else that differs.
2. Upload `<name>.zip` to `bf2/maps/` on static.nihlen.net (the owner's storage box, over FTPS) and check that the
   download's sha512 is the local one.
3. Add the URL to `maps.txt` and `<sha512>  <name>.zip` to `maps.sha512` (both sorted), and
   `maplist.append <name> gpm_cq <size>` to `maplist.con`. Copy the zip into `assets/build/maps/` so the build doesn't
   download it.
4. `tests/run.sh static`, `build <image>`, and `smoke <image>` once with the map first in `maplist.con` (the smoke
   test checks that the first map loads), then put it back.
5. Push to `master`: CI pushes the image, the servers pick it up on their next update.

## Tests

Run from the repo root with bash (Git Bash on Windows); Docker must be running for everything but the first part of
`static`.

```sh
tests/run.sh static                  # asset lists, map lists, the families' shared files, shellcheck
tests/run.sh build <image>...        # build and check the maps inside the image
tests/run.sh smoke <image>...        # start the image and check that the server works
```

Run `static` after every change. After a change to a shared file, build and smoke test at least `openbf2`,
`openbf2-serverext` and one netsky image, since they take different paths through the scripts. A smoke test starts a
server in internet mode, so it may briefly show up on BF2Hub's server list.

Downloads are cached in `assets/build/` (git-ignored): the installer tgz, the OpenBF2 zip, and `maps/`. Copy them from
another image folder instead of downloading them again.

## Conventions

- Scripts are POSIX `sh` and must pass shellcheck at warning level (`tests/.shellcheckrc`).
- `.sh`, `.py`, `.txt`, `.sha512`, `.con` and `extract` are checked out with LF (`.gitattributes`), because they are
  copied into Linux images. Files under `assets/build/levels/` are binary to git and go into a map's `server.zip`
  byte for byte.
- CI builds only the images whose folder changed, or all of them when `tests/`, `.github/` or `.gitattributes`
  changed, and pushes them from the branches in the `PUSH_BRANCHES` repository variable (default `master`). The netsky
  servers pull those tags, so a push to such a branch releases their images.
