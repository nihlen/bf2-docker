#!/bin/sh
set -e

VOLUME='/home/bf2/srv'
TMP='/home/bf2/tmp'

INSTALLER="$TMP/bf2-linuxded-1.5.3153.0-installer.sh"
INSTALLER_TGZ="$TMP/bf2-linuxded-1.5.3153.0-installer.tgz"
MODMANAGER_ZIP="$TMP/ModManager-v2.2c.zip"
OPENBF2_ZIP="$TMP/openbf2-bf2hub-ccf3099-7e37854-glibc-2.32.zip"
MAPS="$TMP/maps"
LEVELS="$TMP/srv/mods/bf2/levels"

# Get required packages
apt -y update
apt-get -y update
apt-get -y install wget expect unzip zip

# Download missing assets listed as "<url> [filename]" and verify their checksums
download_assets() {
    while IFS=" " read url filename
    do
        filename="${filename:-${url##*/}}"
        if [ ! -f "$filename" ]; then
            wget -q --show-progress --progress=bar:force:noscroll -O "$filename" "$url"
        fi
    done < "$1"

    if ! sha512sum -w -c "$2"; then
        echo 'Downloaded file checksum mismatch. Exiting.';
        exit 1;
    fi
}

download_assets assets.txt assets.sha512

# Download custom maps
if [ -f maps.txt ]; then
    mkdir -p "$MAPS"
    (cd "$MAPS" && download_assets "$TMP/maps.txt" "$TMP/maps.sha512")
fi

# Extract server files from the installer
tar -xvf $INSTALLER_TGZ -C $TMP
chmod +x $INSTALLER ./extract
./extract

# Replace the server binaries with OpenBF2
unzip -o $OPENBF2_ZIP -d "$TMP/srv/bin/amd-64"

# Move ModManager files into server directory
unzip $MODMANAGER_ZIP -d "$TMP/srv"

# Clean up unused folders (we have updated pb)
rm -r $TMP/srv/pb_ia-32 $TMP/srv/bin/ia-32

# Remove MD5 files on the NoCheck server to allow client modding
rm -r $TMP/srv/mods/bf2/*.md5

# Extract the server files of the custom maps
# client.zip is only needed by players and archive.md5 enables client file checks, add it to levels/<map> if wanted
if [ -f maps.txt ]; then
    for zip in "$MAPS"/*.zip; do
        unzip -o "$zip" -x '*/client.zip' '*/archive.md5' -d "$LEVELS"
    done

    # Some maps are packaged with an Info folder instead of info
    for dir in "$LEVELS"/*/Info; do
        if [ -d "$dir" ]; then
            mv "$dir" "$(dirname "$dir")/info"
        fi
    done
fi

# Apply our map changes from levels/<map>
# Files in levels/<map>/server.zip are updated inside the map's server.zip, other files are copied to the map folder
if [ -d levels ]; then
    for dir in levels/*/; do
        map=$(basename "$dir")
        if [ -d "$dir/server.zip" ]; then
            (cd "$dir/server.zip" && zip -D -r "$LEVELS/$map/server.zip" .)
        fi
        find "$dir" -mindepth 1 -maxdepth 1 ! -name server.zip -exec cp -r {} "$LEVELS/$map/" \;
    done
fi

# Replace with our own BF2 server files (custom settings and scripts)
cp -r "$TMP/bf2/." "$TMP/srv"

# The server runs the demo hook directly
chmod +x "$TMP/srv/adminutils/demo/rotate_demo.py"

# Create empty server folder to copy our files into if it's empty on the host system
mkdir -p $VOLUME
chmod -R 700 $VOLUME/

exit 0
