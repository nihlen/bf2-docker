#!/bin/sh

# Extract server files from the installer
./extract

# Change owner
chown -R bf2:bf2 /home/bf2/
chmod -R 700 /home/bf2/

exit 0