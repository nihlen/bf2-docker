#!/bin/sh
set -e

HOME_DIR='/home/bf2'
TMP='/home/bf2/tmp'

# Get required packages and create our user
# libncursesw6 + libstdc++6 = run bf2 (OpenBF2) and libbf2hub.so
# libssl3t64 = libserverext.so (the admin channel's TLS)
# python3 = rotate_demo.py
# nginx = host the demos
apt -y update
apt-get -y update
apt-get -y install libncursesw6 libstdc++6 libssl3t64 python3 nginx
apt-get clean
rm -rf /var/lib/apt/lists/*
useradd --create-home --shell /bin/bash bf2

# Replace nginx settings
mv "$TMP/nginx/default" '/etc/nginx/sites-available/'

# run.sh starts the server
mv "$TMP/run.sh" "$HOME_DIR/run.sh"
chmod 755 "$HOME_DIR/run.sh"

# Delete temp files. tests/build/test-image.sh reads the server files from /home/bf2/tmp/srv, so keep that path
rm -rf "$TMP"
mkdir -p "$TMP"
ln -s ../srv "$TMP/srv"

chown -R bf2:bf2 "$HOME_DIR"

exit 0
