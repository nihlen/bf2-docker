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
    replace_pw '{{pw}}' $rcon_pw "$VOLUME/default.profile"
    replace_pw '{{pw}}' $rcon_pw "$VOLUME/mods/bf2/settings/modmanager.con"
    echo "Your RCON password is: $rcon_pw"

    # Set BF2CC Daemon admin password
    daemon_pw="$(generate_pw)"
    daemon_pw_md5="$(echo -n $daemon_pw | md5sum | tr a-z A-Z | tr -d -)"
    replace_pw '{{pw}}' $daemon_pw_md5 "$VOLUME/users.xml"
    echo "Your BF2CC admin password is: $daemon_pw"
fi

# Start nginx
service nginx start

# Start BF2CC Daemon
echo 'Starting BF2CC Daemon...'
export TERM=xterm
su -c "cd $VOLUME && /opt/mono-1.1.12.1/bin/mono ./bf2ccd.exe -noquitprompts -autostart >/dev/null" - bf2

exit 0
