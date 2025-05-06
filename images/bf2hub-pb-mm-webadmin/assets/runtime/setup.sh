#!/bin/sh
set -e

VOLUME='/home/bf2/srv'
WWW='/var/www/html'
DEMOS="$WWW/demos"
TMP='/home/bf2/tmp'

# Get required packages and create our user
# libncurses5 = run bf2
# python = rotate_demo.py
# nginx + php7.4-fpm = host demos and bf2tool.php logs
apt -y update
apt-get -y update
apt-get -y install libncurses5 python nginx php7.4-fpm
apt-get clean
rm -rf /var/lib/apt/lists/*
useradd --create-home --shell /bin/bash bf2

# Replace nginx settings
mv "$TMP/nginx/default" '/etc/nginx/sites-available/'

# Add PHP tool for log files
mv "$TMP/www/bf2tool.php" $WWW

# Delete temp files, but not the temp server directory to move during start
find $TMP/* -maxdepth 0 -type d,f -not -name 'srv' -not -name 'run.sh' -exec rm -r "{}" \;

# Create empty server folder to copy our files into if it's empty on the host system
mkdir -p $VOLUME
chmod -R 700 $VOLUME/

# Create demos web folder
mkdir -p $DEMOS
chmod -R 777 $DEMOS/

# Change owner
chown -R bf2:bf2 /home/bf2/
chmod -R 700 /home/bf2/

exit 0
