"""
Static checks of the image folders, no Docker needed.

Usage: python tests/static/check.py <image folder>...
"""

import os
import re
import sys

STOCK_MAPS = os.path.join(os.path.dirname(__file__), "..", "stock-maps.txt")
IMAGES = os.path.join(os.path.dirname(__file__), "..", "..", "images")
# Image folders are self-contained copies, so these files are kept the same by hand in every image of a family:
# (name, the file that makes an image a member, the files that must be the same in all members)
FAMILIES = [
    ("OpenBF2", "assets/build/bf2/mods/bf2/openbf2.con", [
        ".dockerignore",
        "Dockerfile",
        "assets/build/assets.sha512",
        "assets/build/assets.txt",
        "assets/build/bf2/adminutils/demo/rotate_demo.py",
        "assets/build/bf2/rotate_demo.cfg",
        "assets/build/build.sh",
        "assets/build/extract",
        "assets/runtime/nginx/default",
        "assets/runtime/run.sh",
        "assets/runtime/setup.sh",
    ]),
    ("netsky admin script", "assets/build/bf2/admin/netsky.py", [
        "assets/build/bf2/admin/netsky.py",
    ]),
]
SHA512_LINE = re.compile(r"^[0-9a-f]{128}  (\S+)$")
MAPLIST_LINE = re.compile(r"^\s*maplist\.append\s+(\S+)", re.IGNORECASE)


def read_lines(path):
    with open(path, encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def read_asset_list(path):
    """Return the filenames of an assets.txt style list ("<url> [filename]")."""
    filenames = []
    for line in read_lines(path):
        parts = line.split()
        filenames.append(parts[1] if len(parts) > 1 else parts[0].rsplit("/", 1)[-1])
    return filenames


def check_checksums(image, errors, list_name, sha_name):
    build = os.path.join(image, "assets", "build")
    list_path, sha_path = os.path.join(build, list_name), os.path.join(build, sha_name)
    if not os.path.exists(list_path) and not os.path.exists(sha_path):
        return []
    if not os.path.exists(list_path) or not os.path.exists(sha_path):
        errors.append("%s and %s must both exist" % (list_name, sha_name))
        return []

    filenames = read_asset_list(list_path)
    checksummed = []
    for line in read_lines(sha_path):
        match = SHA512_LINE.match(line)
        if match:
            checksummed.append(match.group(1))
        else:
            errors.append("%s: invalid line '%s'" % (sha_name, line[:60]))

    for name in sorted({n for n in filenames if filenames.count(n) > 1}):
        errors.append("%s: %s is listed more than once" % (list_name, name))
    for name in sorted(set(filenames) - set(checksummed)):
        errors.append("%s: %s has no checksum in %s" % (list_name, name, sha_name))
    for name in sorted(set(checksummed) - set(filenames)):
        errors.append("%s: %s is not listed in %s" % (sha_name, name, list_name))
    return filenames


def map_key(name):
    # Map archives can't start with # in a URL, e.g. #1_sharqi_2v2 is downloaded as 1_sharqi_2v2.zip
    return name.lstrip("#").lower()


def check_maps(image, errors, map_archives):
    stock = {map_key(m) for m in read_lines(STOCK_MAPS)}
    downloaded = {map_key(os.path.splitext(f)[0]) for f in map_archives}
    available = stock | downloaded

    maplist = os.path.join(image, "assets", "build", "bf2", "mods", "bf2", "settings", "maplist.con")
    if os.path.exists(maplist):
        for line in read_lines(maplist):
            match = MAPLIST_LINE.match(line)
            if match and map_key(match.group(1)) not in available:
                errors.append("maplist.con: %s is neither a stock map nor in maps.txt" % match.group(1))

    levels = os.path.join(image, "assets", "build", "levels")
    if os.path.isdir(levels):
        for name in sorted(os.listdir(levels)):
            path = os.path.join(levels, name)
            if not os.path.isdir(path):
                errors.append("levels/%s: expected a map folder" % name)
                continue
            if map_key(name) not in available:
                errors.append("levels/%s: map is neither a stock map nor in maps.txt" % name)
            server_zip = os.path.join(path, "server.zip")
            if os.path.isfile(server_zip):
                errors.append("levels/%s/server.zip: must be a folder with the changed files, not a zip" % name)
            elif os.path.isdir(server_zip) and not any(files for _, _, files in os.walk(server_zip)):
                errors.append("levels/%s/server.zip: folder is empty" % name)


def read_normalized(path):
    """The file's bytes with LF line endings (a Windows checkout has CRLF in some files), None if it is missing."""
    if not os.path.isfile(path):
        return None
    with open(path, "rb") as f:
        return f.read().replace(b"\r\n", b"\n")


def check_families(images_dir):
    """Check every image folder, whichever images were asked for: a change to one image can break its family."""
    errors = []
    images = sorted(d for d in os.listdir(images_dir) if os.path.isfile(os.path.join(images_dir, d, "Dockerfile")))
    for name, marker, shared in FAMILIES:
        members = [i for i in images if os.path.isfile(os.path.join(images_dir, i, *marker.split("/")))]
        for path in shared:
            # The images grouped by the content of the file
            groups = {}
            for image in members:
                groups.setdefault(read_normalized(os.path.join(images_dir, image, *path.split("/"))), []).append(image)
            if len(groups) > 1:
                parts = ["%s (%s)" % (", ".join(group), "missing" if content is None else "%d bytes" % len(content))
                         for content, group in sorted(groups.items(), key=lambda item: item[1])]
                errors.append("%s images: %s differs: %s" % (name, path, " / ".join(parts)))
    return errors


def main(images):
    failed = False
    family_errors = check_families(IMAGES)
    for error in family_errors:
        print("FAIL %s" % error)
    if not family_errors:
        print("ok   shared files are the same within each image family")
    failed = bool(family_errors)
    for image in images:
        errors = []
        check_checksums(image, errors, "assets.txt", "assets.sha512")
        map_archives = check_checksums(image, errors, "maps.txt", "maps.sha512")
        check_maps(image, errors, map_archives)

        name = os.path.basename(os.path.normpath(image))
        for error in errors:
            print("FAIL %s: %s" % (name, error))
        if not errors:
            print("ok   %s" % name)
        failed = failed or bool(errors)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
