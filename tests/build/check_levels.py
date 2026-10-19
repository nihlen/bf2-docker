"""
Checks the maps of a built image, copied out of the container by test-image.sh.

Usage: python tests/build/check_levels.py <image folder> <output folder with levels/ and maplist.con>
"""

import os
import re
import sys
import zipfile

MAPLIST_LINE = re.compile(r"^\s*maplist\.append\s+(\S+)", re.IGNORECASE)


def read_maplist(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return [m.group(1) for m in map(MAPLIST_LINE.match, f) if m]


def read_file(path):
    with open(path, "rb") as f:
        return f.read()


def check_maplist(levels, maplist, errors):
    for name in read_maplist(maplist):
        if not os.path.isfile(os.path.join(levels, name, "server.zip")):
            errors.append("maplist map %s has no %s/server.zip" % (name, name))


def check_level_folders(levels, errors):
    for name in sorted(os.listdir(levels)):
        path = os.path.join(levels, name)
        if not os.path.isdir(path):
            continue
        if os.path.exists(os.path.join(path, "client.zip")):
            errors.append("%s: client.zip is not needed on the server" % name)
        if "Info" in os.listdir(path):
            errors.append("%s: Info folder should be named info" % name)

        server_zip = os.path.join(path, "server.zip")
        if not os.path.isfile(server_zip):
            continue
        try:
            with zipfile.ZipFile(server_zip) as z:
                names = [n.lower() for n in z.namelist()]
                duplicates = sorted({n for n in names if names.count(n) > 1})
                if duplicates:
                    errors.append("%s/server.zip: duplicate entries %s" % (name, ", ".join(duplicates[:5])))
                bad = z.testzip()
                if bad:
                    errors.append("%s/server.zip: corrupt entry %s" % (name, bad))
        except zipfile.BadZipFile as e:
            errors.append("%s/server.zip: %s" % (name, e))


def check_level_changes(image, levels, errors):
    """Every file in assets/build/levels must end up in the built map, in server.zip or the map folder."""
    changes = os.path.join(image, "assets", "build", "levels")
    if not os.path.isdir(changes):
        return
    for root, _, files in os.walk(changes):
        for file in files:
            source = os.path.join(root, file)
            rel = os.path.relpath(source, changes).replace("\\", "/")
            map_name, _, path = rel.partition("/")
            if path.startswith("server.zip/"):
                entry = path[len("server.zip/"):]
                server_zip = os.path.join(levels, map_name, "server.zip")
                try:
                    with zipfile.ZipFile(server_zip) as z:
                        data = z.read(entry)
                except (OSError, KeyError, zipfile.BadZipFile):
                    errors.append("levels/%s: %s not found in %s/server.zip" % (rel, entry, map_name))
                    continue
            else:
                target = os.path.join(levels, map_name, *path.split("/"))
                if not os.path.isfile(target):
                    errors.append("levels/%s: not found in the built map" % rel)
                    continue
                data = read_file(target)
            if data != read_file(source):
                errors.append("levels/%s: built file differs" % rel)


def main(image, output):
    levels = os.path.join(output, "levels")
    errors = []
    check_maplist(levels, os.path.join(output, "maplist.con"), errors)
    check_level_folders(levels, errors)
    check_level_changes(image, levels, errors)

    name = os.path.basename(os.path.normpath(image))
    for error in errors:
        print("FAIL %s: %s" % (name, error))
    if not errors:
        print("ok   %s: %d maps" % (name, len(os.listdir(levels))))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:3]))
