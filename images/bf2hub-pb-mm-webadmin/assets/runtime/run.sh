#!/bin/sh
set -e

TMP='/home/bf2/tmp'
SRV='/home/bf2/srv'
VOLUME='/volume'

generate_pw() {
    echo "$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c10)"
}

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
    mkdir -m 777 -p $VOLUME/svlogs
    mkdir -m 777 -p $VOLUME/svss
    mkdir -m 777 -p $VOLUME/demos
    mkdir -m 777 -p $VOLUME/demos/pending
    mkdir -m 777 -p $VOLUME/demos/uploaded
    mkdir -m 777 -p $VOLUME/www
    install -m 777 /dev/null $VOLUME/bf2.log
    install -m 777 /dev/null $VOLUME/modmanager.log
    install -m 777 /dev/null $VOLUME/pbalias.dat
    install -m 777 /dev/null $VOLUME/sv_viol.log
    mv -n $SRV/mods/bf2/settings $VOLUME
    chmod -R 777 $VOLUME/settings
    mv -n /var/www/html/bf2tool.php $VOLUME/www
    rm -rf $SRV/mods/bf2/demos
    rm -rf $SRV/pb_amd-64/svss
    rm -rf $SRV/pb_amd-64/svlogs
    ln -sf $VOLUME/settings $SRV/mods/bf2/settings
    ln -sf $VOLUME/demos/pending $SRV/mods/bf2/demos
    ln -sf $VOLUME/svss $SRV/pb_amd-64/svss
    ln -sf $VOLUME/svlogs $SRV/pb_amd-64/svlogs
    ln -sf $VOLUME/bf2.log $SRV/bf2.log
    ln -sf $VOLUME/modmanager.log $SRV/modmanager.log
    ln -sf $VOLUME/pbalias.dat $SRV/pbalias.dat
    ln -sf $VOLUME/sv_viol.log $SRV/pb_amd-64/sv_viol.log

    # Set execute permissions
    echo 'Setting execute permissions...'
    cd $SRV
    chmod +x ./start_bf2hub.sh ./bin/amd-64/bf2
    chmod -R 777 ./pb_amd-64
    chmod -R 777 . # temp D:

    # Set server settings from environment variables
    replace_var '{{server_name}}' "${ENV_SERVER_NAME:-"bf2-docker"}" "$SRV/mods/bf2/settings/serversettings.con"
    replace_var '{{max_players}}' "${ENV_MAX_PLAYERS:-"16"}" "$SRV/mods/bf2/settings/serversettings.con"
    replace_var '{{server_port}}' "${ENV_SERVER_PORT:-"16567"}" "$SRV/mods/bf2/settings/serversettings.con"
    replace_var '{{gamespy_port}}' "${ENV_GAMESPY_PORT:-"29900"}" "$SRV/mods/bf2/settings/serversettings.con"
    replace_var '{{demos_url}}' "${ENV_DEMOS_URL:-"http://example.com/demos/"}" "$SRV/mods/bf2/settings/serversettings.con"
    replace_var '{{rcon_password}}' "${ENV_RCON_PASSWORD:-"$(generate_pw)"}" "$SRV/mods/bf2/settings/modmanager.con"
    replace_var '{{bf2wa_host}}' "${ENV_BF2WEBADMIN_HOST:-"host.docker.internal"}" "$SRV/mods/bf2/settings/modmanager.con"
    replace_var '{{bf2wa_port}}' "${ENV_BF2WEBADMIN_PORT:-"4300"}" "$SRV/mods/bf2/settings/modmanager.con"
    replace_var '{{bf2wa_timer_interval}}' "${ENV_BF2WEBADMIN_TIMER_INTERVAL:-"0.25"}" "$SRV/mods/bf2/settings/modmanager.con"
    replace_var '{{api_key}}' "${ENV_API_KEY:-"$(generate_pw)"}" "$VOLUME/www/bf2tool.php" 
fi

# Start nginx and php
service nginx start
service php7.0-fpm start

# Start Battlefield 2 server as the bf2 user
echo "Starting Battlefield 2 server..."
export TERM=xterm
su -c "cd $SRV && ./start_bf2hub.sh >bf2.log" - bf2

exit 0
