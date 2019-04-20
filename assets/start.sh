#!/bin/sh
set -e

TMP='/home/bf2/tmp'
VOLUME='/home/bf2/srv'

# Check if target volume is empty
if [ "$(ls -A $VOLUME)" ]; then
    echo "$VOLUME is not empty. Skipping..."
else
    # Move server files to persisted folder (-n without overwriting)
    echo "$VOLUME is empty. Moving server files..."
    mv -n $TMP/srv/* $VOLUME/

    # Set permissions
    echo 'Setting execute permissions...'
    cd $VOLUME
    chmod +x ./start_bf2hub.sh ./bin/amd-64/bf2
fi

# Start Battlefield 2 server
echo "Starting Battlefield 2 server..."
export TERM=xterm
su -c "cd $VOLUME && ./start_bf2hub.sh >/dev/null" - bf2

exit 0
