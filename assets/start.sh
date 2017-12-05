#!/bin/sh

TMP="/home/bf2/tmp"
VOLUME="/home/bf2"

SRC="$TMP/srv/"
DEST="$VOLUME/srv/"

# Move from temp to persisted folder (symlink instead?)
if [ "$(ls -A $DEST)" ]; then
    echo "$DEST is not empty"
else
    echo "$DEST is empty. Moving server files..."

    # Move server files (-n without overwriting)
    mv -n $SRC* $DEST

    # Overwrite settings file
    mv "$TMP/serversettings.con" "$DEST/mods/bf2/settings/"

    # Delete our tmp directory
    rm -rf $SRC
fi

# Start Battlefield 2 server
export TERM=xterm
cd $DEST
./start.sh