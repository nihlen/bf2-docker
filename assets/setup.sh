#!/bin/sh
set -e

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

MONOINSTALLER="$TMP/mono-1.1.12.1_0-installer.bin"
MONOINSTALLER_URL='https://download.mono-project.com/archive/1.1.12.1/linux-installer/0/mono-1.1.12.1_0-installer.bin'
MONOINSTALLER_SHA512='c9557048a70e4bbd28a51fa55ce58a87cf652f03329d792621eb22d45dcc9f3f2301cbab0e27944c265ccdd9b8a45d818e1f4dc469c31d5f6fc3df1bbc54cec1'

BF2CCD_ZIP="$TMP/BF2CCD_1.4.2446.zip"
BF2CCD_URL='https://www.fullcontactwar.com/files/BF2CCD_1.4.2446.zip'
BF2CCD_SHA512='ee734acba5f3f0fddf3e10e448d03af9de03713425c8844ae31b534eca3904c21abd413d105e7039fde5bd0f855971997ad61caf67fde6156e9b212e426b99d1'

download_and_verify() {
    if [[ ! -e $1 ]]; then
        echo "Downloading $2..."
        wget $2 -O $1

        # Validate checksum
        if [[ $3 != $(sha512sum $1) ]]; then
            echo 'Downloaded file checksum mismatch. Exiting.';
            exit 1;
        fi
    fi
}

download_and_verify $INSTALLER_TGZ $INSTALLER_URL $INSTALLER_SHA512
download_and_verify $BF2HUB_TGZ $BF2HUB_URL $BF2HUB_SHA512
download_and_verify $MODMANAGER_ZIP $MODMANAGER_URL $MODMANAGER_SHA512
download_and_verify $MONOINSTALLER $MONOINSTALLER_URL $MONOINSTALLER_SHA512
download_and_verify $BF2CCD_ZIP $BF2CCD_URL $BF2CCD_SHA512

# Extract server files from the installer
tar -xvf $INSTALLER_TGZ -C $TMP
chmod +x $INSTALLER
chmod +x ./extract
./extract

# Move BF2Hub files into server directory
tar -xvf $BF2HUB_TGZ -C "$TMP/srv"

# Move ModManager files into server directory
unzip $MODMANAGER_ZIP -d "$TMP/srv"

# Install Mono
chmod +x $MONOINSTALLER
$MONOINSTALLER

# Move BF2CC Daemon into server directory
unzip $BF2CCD_ZIP -d "$TMP/srv"

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