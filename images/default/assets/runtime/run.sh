#!/bin/sh
set -e

TMP='/home/bf2/tmp'
SRV='/home/bf2/srv'
VOLUME='/volume'

replace_var() {
    echo "$3: $1 => $2"
    replaceEscaped=$(echo "$2" | sed 's/[&/\]/\\&/g')
    sed -i -e "s/$1/$replaceEscaped/g" $3
}

# Check if target volume is empty
if [ "$(ls -A $SRV)" ]; then
    echo "$SRV is not empty. Skipping..."
else
    # Move server files to persisted folder (-n without overwriting)
    echo "$SRV is empty. Moving server files..."
    mv -n $TMP/srv/* $SRV/

    # Create volume directory for all persisted changes
    echo 'Moving persisted data and creating symlinks...'
    mkdir -m 777 -p $VOLUME
    install -m 777 /dev/null $VOLUME/bf2.log
    install -m 777 /dev/null $VOLUME/pbalias.dat
    install -m 777 /dev/null $VOLUME/sv_viol.log
    mv -n $SRV/mods/bf2/settings $VOLUME
    chmod -R 777 $VOLUME/settings
    ln -sf $VOLUME/settings $SRV/mods/bf2/settings
    ln -sf $VOLUME/bf2.log $SRV/bf2.log
    ln -sf $VOLUME/pbalias.dat $SRV/pbalias.dat

    # Set execute permissions
    echo 'Setting execute permissions...'
    cd $SRV
    chmod +x ./start.sh ./bin/amd-64/bf2
    chmod -R 777 . # temp D:

    # Set server settings from environment variables
    replace_var '{{server_name}}' "${ENV_SERVER_NAME:-"bf2-docker"}" "$SRV/mods/bf2/settings/serversettings.con"
    replace_var '{{max_players}}' "${ENV_MAX_PLAYERS:-"16"}" "$SRV/mods/bf2/settings/serversettings.con"
    replace_var '{{server_port}}' "${ENV_SERVER_PORT:-"16567"}" "$SRV/mods/bf2/settings/serversettings.con"
    replace_var '{{gamespy_port}}' "${ENV_GAMESPY_PORT:-"29900"}" "$SRV/mods/bf2/settings/serversettings.con"
fi

# Start Battlefield 2 server as the bf2 user
echo "Starting Battlefield 2 server..."
export TERM=xterm
su -c "cd $SRV && ./start.sh >bf2.log" - bf2

exit 0
