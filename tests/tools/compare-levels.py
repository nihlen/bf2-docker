"""
Compares two levels folders, e.g. the maps of a running server with the maps of a new build.
Zip files are compared entry by entry, so repacked zips with the same contents are equal.

Usage: python tests/tools/compare-levels.py <reference levels> <levels> [map...]

Get the levels of a build with: tests/run.sh build --keep <image> (written to tests/out/<image>/levels)
"""

import os
import sys
import zipfile


def list_files(folder):
    files = {}
    for root, _, names in os.walk(folder):
        for name in names:
            path = os.path.join(root, name)
            files[os.path.relpath(path, folder).replace("\\", "/")] = path
    return files


def zip_entries(path):
    with zipfile.ZipFile(path) as z:
        return {i.filename: i.CRC for i in z.infolist() if not i.is_dir()}


def read_file(path):
    with open(path, "rb") as f:
        return f.read()


def compare_map(reference, current):
    ref_files, cur_files = list_files(reference), list_files(current)
    differences = []
    for rel in sorted(set(ref_files) | set(cur_files)):
        if rel not in cur_files:
            differences.append("missing   " + rel)
        elif rel not in ref_files:
            differences.append("added     " + rel)
        elif rel.lower().endswith(".zip"):
            ref_zip, cur_zip = zip_entries(ref_files[rel]), zip_entries(cur_files[rel])
            for entry in sorted(set(ref_zip) | set(cur_zip)):
                if entry not in cur_zip:
                    differences.append("missing   %s: %s" % (rel, entry))
                elif entry not in ref_zip:
                    differences.append("added     %s: %s" % (rel, entry))
                elif ref_zip[entry] != cur_zip[entry]:
                    differences.append("changed   %s: %s" % (rel, entry))
        elif read_file(ref_files[rel]) != read_file(cur_files[rel]):
            differences.append("changed   " + rel)
    return differences


def main(reference, current, maps):
    if not maps:
        maps = sorted(set(os.listdir(reference)) | set(os.listdir(current)))
    changed = 0
    for name in maps:
        ref_map, cur_map = os.path.join(reference, name), os.path.join(current, name)
        if not os.path.isdir(cur_map):
            print("%-28s missing map" % name)
        elif not os.path.isdir(ref_map):
            print("%-28s added map" % name)
        else:
            differences = compare_map(ref_map, cur_map)
            print("%-28s %s" % (name, "identical" if not differences else "%d differences" % len(differences)))
            for difference in differences:
                print("    " + difference)
            changed += bool(differences)
            continue
        changed += 1
    print("\n%d of %d maps differ" % (changed, len(maps)))
    return 1 if changed else 0


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__.strip())
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3:]))
