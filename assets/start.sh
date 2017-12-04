#!/bin/sh

# Move from temp to persisted folder (symlink instead?)
mv -n /home/bf2/tmp/srv/* /home/bf2/srv/
rm -rf /home/bf2/tmp/

# Replace serversettings.con
# TODO

# Start Battlefield 2 server
export TERM=xterm
cd /home/bf2/srv
./start.sh