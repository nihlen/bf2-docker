#!/bin/sh

TMP='/home/bf2/tmp'
INSTALLER="$TMP/bf2-linuxded-1.5.3153.0-installer.sh"
INSTALLER_GZ="$TMP/bf2-linuxded-1.5.3153.0-installer.tgz"
INSTALLER_URL='https://www.bf-games.net/downloads/954/bf2-dedicated-server-1-50-linux-build-1-5-3153-802-0.html?downloadnow&mirror=31635'
INSTALLER_MD5='fa7bb15ab74ce3504339907f53f91f2b'

# Verify that we have the required files
if [[ ! -e $INSTALLER ]]; then
    echo 'Downloading BF2 Dedicated Server 1.5.3153-802.0...'
    wget $INSTALLER_URL -O $INSTALLER_GZ
    tar -xvf $INSTALLER_GZ -C $TMP

    # Check MD5
    MD5=($(md5sum $INSTALLER))
    if [[ $MD5 != $INSTALLER_MD5 ]]; then
        echo 'Downloaded installer MD5 mismatch. Exiting.';
        exit 1;
    fi
fi

# Extract server files from the installer
./extract

# Change owner
chown -R bf2:bf2 /home/bf2/
chmod -R 700 /home/bf2/

exit 0