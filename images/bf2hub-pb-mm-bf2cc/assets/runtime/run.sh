#!/bin/sh
set -e

TMP='/home/bf2/tmp'
SRV='/home/bf2/srv'
VOLUME='/volume'

generate_pw() {
    echo "$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c10)"
}

replace_var() {
    echo "$3: $1 => [$2]"
    replaceEscaped=$(echo "$2" | sed 's/[&/\]/\\&/g')
    sed -i --follow-symlinks -e "s/$1/$replaceEscaped/g" $3
}

# Check if target volume is empty
if [ "$(ls -A $SRV)" ]; then
    echo "$SRV is not empty. Skipping..."
else
    # Move server files to persisted folder (-n without overwriting)
    echo "$SRV is empty. Moving server files..."
    mv -n $TMP/srv/* $SRV/

    # Set server settings from environment variables
    rcon_pw="${ENV_RCON_PASSWORD:-"$(generate_pw)"}"
    bf2ccd_pw="${ENV_BF2CCD_PASSWORD:-"$(generate_pw)"}"
    bf2ccd_pw_md5="$(echo -n $bf2ccd_pw | md5sum | tr a-z A-Z | tr -d - | xargs echo -n)"
    replace_var '{{server_name}}' "${ENV_SERVER_NAME:-"bf2-docker"}" "$SRV/mods/bf2/settings/serversettings.con"
    replace_var '{{max_players}}' "${ENV_MAX_PLAYERS:-"16"}" "$SRV/mods/bf2/settings/serversettings.con"
    replace_var '{{server_port}}' "${ENV_SERVER_PORT:-"16567"}" "$SRV/mods/bf2/settings/serversettings.con"
    replace_var '{{server_port}}' "${ENV_SERVER_PORT:-"16567"}" "$SRV/bf2ccd/default.profile"
    replace_var '{{gamespy_port}}' "${ENV_GAMESPY_PORT:-"29900"}" "$SRV/mods/bf2/settings/serversettings.con"
    replace_var '{{gamespy_port}}' "${ENV_GAMESPY_PORT:-"29900"}" "$SRV/bf2ccd/default.profile"
    replace_var '{{demos_url}}' "${ENV_DEMOS_URL:-"http://example.com/demos/"}" "$SRV/mods/bf2/settings/serversettings.con"
    replace_var '{{rcon_password}}' "$rcon_pw" "$SRV/mods/bf2/settings/modmanager.con"
    replace_var '{{rcon_password}}' "$rcon_pw" "$SRV/bf2ccd/default.profile"
    replace_var '{{bf2ccd_password}}' "$bf2ccd_pw_md5" "$SRV/bf2ccd/users.xml"

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
    mv -n $SRV/bf2ccd $VOLUME
    chmod -R 777 $VOLUME/bf2ccd
    ln -sf $VOLUME/bf2ccd $SRV/bf2ccd

    # Set execute permissions
    echo 'Setting execute permissions...'
    cd $SRV
    chmod +x ./start_bf2hub.sh ./bin/amd-64/bf2 ./mono-1.1.12.1/bin/mono ./bf2ccd/bf2ccd.exe
    chmod -R 777 ./pb_amd-64
    chmod -R 777 ./bf2ccd
    chmod -R 777 . # temp D:
fi

# Start nginx for demos
service nginx start

# Start BF2CC Daemon
echo 'Starting BF2CC Daemon...'
export TERM=xterm
su -c "cd $SRV && ./mono-1.1.12.1/bin/mono ./bf2ccd/bf2ccd.exe -noquitprompts -autostart >/dev/null" - bf2

exit 0
