#!/bin/sh
set -e

TMP='/home/bf2/tmp'
VOLUME='/home/bf2/srv'

generate_pw() {
    echo "$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c10)"
}

replace_pw() {
    sed -i -e "s/$1/$2/g" $3
}

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

    # Set RCON password
    rcon_pw="$(generate_pw)"
    replace_pw '{{pw}}' $rcon_pw "$VOLUME/mods/bf2/settings/modmanager.con"
    echo "Your RCON password is: $rcon_pw"
fi

# Start nginx
service nginx start

# Start Battlefield 2 server
echo "Starting Battlefield 2 server..."
export TERM=xterm
su -c "cd $VOLUME && ./start_bf2hub.sh >/dev/null" - bf2

exit 0
