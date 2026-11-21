"""
Repacks a map archive for static.nihlen.net: one top folder named <name> (lowercase), info/<name>.desc named after the
folder, and optionally some entries removed from server.zip (e.g. a stale map.desc). Every other file is copied byte
for byte, client.zip untouched.

Usage: python -I tests/tools/repack-map.py <map.zip> <out.zip> <name> [server.zip entry to remove...]

Example: python -I tests/tools/repack-map.py DF_BLACKHOLE8.zip df_blackhole8.zip df_blackhole8 map.desc
"""

import io
import sys
import zipfile


def copy_info(info, name):
    out = zipfile.ZipInfo(name, info.date_time)
    out.compress_type = zipfile.ZIP_STORED if name.lower().endswith(".zip") else zipfile.ZIP_DEFLATED
    out.external_attr = info.external_attr
    return out


def repack_server_zip(data, remove):
    out = io.BytesIO()
    removed = set()
    with zipfile.ZipFile(io.BytesIO(data)) as zin, zipfile.ZipFile(out, "w") as zout:
        for info in zin.infolist():
            if info.filename.lower() in remove:
                removed.add(info.filename.lower())
                print("server.zip: removed %s" % info.filename)
                continue
            zout.writestr(copy_info(info, info.filename), zin.read(info.filename), compresslevel=9)
    for name in sorted(remove - removed):
        sys.exit("server.zip has no %s" % name)
    return out.getvalue()


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    source, target, name = sys.argv[1], sys.argv[2], sys.argv[3]
    remove = {entry.replace("\\", "/").lower() for entry in sys.argv[4:]}
    if name != name.lower():
        sys.exit("the map name must be lowercase")

    with zipfile.ZipFile(source) as zin, zipfile.ZipFile(target, "w") as zout:
        tops = {i.filename.split("/")[0] for i in zin.infolist()}
        if len(tops) != 1:
            sys.exit("expected one top folder, found %s" % ", ".join(sorted(tops)))
        top = tops.pop()
        for info in zin.infolist():
            if info.is_dir():
                continue
            rel = info.filename[len(top) + 1:]
            data = zin.read(info.filename)
            # Some maps have an Info folder, and a .desc named in another case than the folder
            if rel.lower().startswith("info/"):
                rel = "info/" + rel[5:]
                if rel.lower() == "info/%s.desc" % name:
                    rel = "info/%s.desc" % name
            if rel == "server.zip" and remove:
                data = repack_server_zip(data, remove)
            zout.writestr(copy_info(info, "%s/%s" % (name, rel)), data, compresslevel=9)
            if rel != info.filename[len(top) + 1:] or top != name:
                print("%s -> %s/%s" % (info.filename, name, rel))

    with zipfile.ZipFile(target) as z:
        bad = z.testzip()
        if bad:
            sys.exit("corrupt entry %s" % bad)


if __name__ == "__main__":
    main()
