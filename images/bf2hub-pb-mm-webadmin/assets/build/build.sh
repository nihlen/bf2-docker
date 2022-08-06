#!/bin/sh
set -e

VOLUME='/home/bf2/srv'
TMP='/home/bf2/tmp'

INSTALLER="$TMP/bf2-linuxded-1.5.3153.0-installer.sh"
INSTALLER_TGZ="$TMP/bf2-linuxded-1.5.3153.0-installer.tgz"
BF2HUB_TGZ="$TMP/BF2Hub-Unranked-Linux-R3.tar.gz"
MODMANAGER_ZIP="$TMP/ModManager-v2.2c.zip"

# Get required packages
apt -y update
apt-get -y update
apt-get -y install wget expect unzip

# Download missing assets
wget -nc -q --show-progress --progress=bar:force:noscroll -i assets.txt

# Verify checksums
if ! sha512sum -w -c assets.sha512; then
    echo 'Downloaded file checksum mismatch. Exiting.';
    exit 1;
fi

# Extract server files from the installer
tar -xvf $INSTALLER_TGZ -C $TMP
chmod +x $INSTALLER ./extract
./extract

# Move BF2Hub files into server directory
tar -xvf $BF2HUB_TGZ -C "$TMP/srv"

# Move ModManager files into server directory
unzip $MODMANAGER_ZIP -d "$TMP/srv"

# Clean up unused folders (we have updated pb)
rm -r $TMP/srv/pb_* $TMP/srv/bin/ia-32

# Replace with our own BF2 server files (custom settings and scripts)
cp -r "$TMP/bf2/." "$TMP/srv"

# Create empty server folder to copy our files into if it's empty on the host system
mkdir -p $VOLUME
chmod -R 700 $VOLUME/

exit 0
