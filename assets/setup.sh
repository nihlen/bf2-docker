#!/bin/sh

TMP='/home/bf2/tmp'

INSTALLER="$TMP/bf2-linuxded-1.5.3153.0-installer.sh"
INSTALLER_TGZ="$TMP/bf2-linuxded-1.5.3153.0-installer.tgz"
INSTALLER_URL='ftp://ftp.bf-games.net/server-files/bf2/bf2-linuxded-1.5.3153.0-installer.tgz'
INSTALLER_MD5='fa7bb15ab74ce3504339907f53f91f2b'

BF2HUB_TGZ="$TMP/BF2Hub-Unranked-Linux-R3.tar.gz"
BF2HUB_URL='https://www.bf2hub.com/downloads/BF2Hub-Unranked-Linux-R3.tar.gz'

# Verify that we have the required server files
if [[ ! -e $INSTALLER ]]; then
    echo 'Downloading BF2 Dedicated Server 1.5.3153-802.0...'
    wget $INSTALLER_URL -O $INSTALLER_TGZ
    tar -xvf $INSTALLER_TGZ -C $TMP

    # Check MD5
    MD5=($(md5sum $INSTALLER))
    if [[ $MD5 != $INSTALLER_MD5 ]]; then
        echo 'Downloaded installer MD5 mismatch. Exiting.';
        exit 1;
    fi
fi

# Verify that we have the BF2Hub files required for online
if [[ ! -e $BF2HUB_TGZ ]]; then
    echo 'Downloading BF2Hub Unranked Linux R3...'
    wget $BF2HUB_URL -O $BF2HUB_TGZ
fi

# Extract server files from the installer
chmod +x $INSTALLER
chmod +x ./extract
./extract

# Move BF2Hub files into server directory
tar -xvf $BF2HUB_TGZ -C "$TMP/srv"

# Change owner
chown -R bf2:bf2 /home/bf2/
chmod -R 700 /home/bf2/

exit 0