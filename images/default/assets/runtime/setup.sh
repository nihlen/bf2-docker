#!/bin/sh
set -e

VOLUME='/home/bf2/srv'
TMP='/home/bf2/tmp'

# Get required packages and create our user
# libncurses5 = run bf2
apt -y update
apt-get -y update
apt-get -y install libncurses5
apt-get clean
rm -rf /var/lib/apt/lists/*
useradd --create-home --shell /bin/bash bf2

# Delete temp files, but not the temp server directory to move during start
find $TMP/* -maxdepth 0 -type d,f -not -name 'srv' -not -name 'run.sh' -exec rm -r "{}" \;

# Create empty server folder to copy our files into if it's empty on the host system
mkdir -p $VOLUME
chmod -R 700 $VOLUME/

# Change owner
chown -R bf2:bf2 /home/bf2/
chmod -R 700 /home/bf2/

exit 0
