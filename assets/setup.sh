#!/bin/sh
set -e

VOLUME='/home/bf2/srv'
DEMOS='/var/www/html/demos'
TMP='/home/bf2/tmp'

INSTALLER="$TMP/bf2-linuxded-1.5.3153.0-installer.sh"
INSTALLER_TGZ="$TMP/bf2-linuxded-1.5.3153.0-installer.tgz"
BF2HUB_TGZ="$TMP/BF2Hub-Unranked-Linux-R3.tar.gz"
MODMANAGER_ZIP="$TMP/ModManager-v2.2c.zip"

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

# Replace with our own BF2 server files (custom settings and scripts)
cp -r "$TMP/bf2/." "$TMP/srv"

# Replace nginx settings
mv "$TMP/nginx/default" '/etc/nginx/sites-available/'

# Delete temp files, but not the temp server directory to move during start
rm -f "$TMP/*"

# Create empty server folder to copy our files into if it's empty on the host system
mkdir -p $VOLUME
chmod -R 700 $VOLUME/

# Create demos web folder
mkdir -p $DEMOS
chmod -R 700 $DEMOS/

# Change owner
chown -R bf2:bf2 /home/bf2/
chmod -R 700 /home/bf2/

exit 0
