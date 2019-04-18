#!/bin/sh

VOLUME='/home/bf2/srv'
DEMOS='/var/www/html/demos'
TMP='/home/bf2/tmp'

INSTALLER="$TMP/bf2-linuxded-1.5.3153.0-installer.sh"
INSTALLER_TGZ="$TMP/bf2-linuxded-1.5.3153.0-installer.tgz"
INSTALLER_URL='ftp://ftp.bf-games.net/server-files/bf2/bf2-linuxded-1.5.3153.0-installer.tgz'
INSTALLER_SHA512='b807684116a0f3d2590390567a5a0da8fa9b0804fb9229ae056fa4cad2d8a46cd306d39592a04167c8b757083e4d20a1d28fe04154c25dab3156ef8be9db3702'

BF2HUB_TGZ="$TMP/BF2Hub-Unranked-Linux-R3.tar.gz"
BF2HUB_URL='https://www.bf2hub.com/downloads/BF2Hub-Unranked-Linux-R3.tar.gz'
BF2HUB_SHA512='8391cac06f6667ad4cb495e5ed907159b67ac7c9cb5a1d5fa337d363d95d378767382326add388d06c511653a6295241f64eceffc4648b524cede89e0479a84d'

MODMANAGER_ZIP="$TMP/ModManager-v2.2c.zip"
MODMANAGER_URL='http://blog.multiplay.co.uk/dropzone/ModManager-v2.2c.zip'
MODMANAGER_SHA512='d025aff1a6713da0381b8844f64cd016a66ab907bc936e74ca31ef0781424c02597116c322044da46877766318f28c4c4822e5c4bdec1c19a90157c39fe5bbb4'

# Verify that we have the required server files
if [[ ! -e $INSTALLER_TGZ ]]; then
    echo 'Downloading BF2 Dedicated Server 1.5.3153-802.0...'
    wget $INSTALLER_URL -O $INSTALLER_TGZ

    # Validate checksum
    SHA512=($(sha512sum $INSTALLER_TGZ))
    if [[ $SHA512 != $INSTALLER_SHA512 ]]; then
        echo 'Downloaded installer checksum mismatch. Exiting.';
        exit 1;
    fi
fi

# Verify that we have the BF2Hub files required for online
if [[ ! -e $BF2HUB_TGZ ]]; then
    echo 'Downloading BF2Hub Unranked Linux R3...'
    wget $BF2HUB_URL -O $BF2HUB_TGZ

    # Validate checksum
    SHA512=($(sha512sum $BF2HUB_TGZ))
    if [[ $SHA512 != $BF2HUB_SHA512 ]]; then
        echo 'Downloaded BF2Hub checksum mismatch. Exiting.';
        exit 1;
    fi
fi

# Verify that we have the ModManager files
if [[ ! -e $MODMANAGER_ZIP ]]; then
    echo 'Downloading ModManager v2.2c...'
    wget $MODMANAGER_URL -O $MODMANAGER_ZIP

    # Validate checksum
    SHA512=($(sha512sum $MODMANAGER_ZIP))
    if [[ $SHA512 != $MODMANAGER_SHA512 ]]; then
        echo 'Downloaded ModManager checksum mismatch. Exiting.';
        exit 1;
    fi
fi

# Extract server files from the installer
tar -xvf $INSTALLER_TGZ -C $TMP
chmod +x $INSTALLER
chmod +x ./extract
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