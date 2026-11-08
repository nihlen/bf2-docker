#!/bin/sh
# Starts the server. Runs on every container start, so a new image or a changed environment variable always takes
# effect: the server files come from the image, the settings are rendered from the templates in /home/bf2/templates
# and the environment, and only the state below is kept in /volume (mount it to keep the state; nothing else needs
# a mount, and /home/bf2/srv must not be mounted):
#   /volume/settings/banlist.con     BF2's ban list
#   /volume/settings/mm_bans.xml     ModManager's ban list (iga ban)
#   /volume/demos/pending            demos being recorded (mods/bf2/demos)
#   /volume/demos/uploaded           finished demos, served by nginx at /demos/ (rotate_demo.py keeps 50)
#   /volume/bf2.log                  the server console of this start (bf2.log.1: the previous start)
#   /volume/modmanager.log           ModManager's log of this start (modmanager.log.1: the previous start)
#   /volume/logs                     module logs (logs/bf2hub)
set -e

SRV='/home/bf2/srv'
SETTINGS="$SRV/mods/bf2/settings"
TEMPLATES='/home/bf2/templates'
WWW='/home/bf2/www'
VOLUME='/volume'

fail() {
    echo "run.sh: $*" >&2
    exit 1
}

generate_pw() {
    tr -dc '_A-Za-z0-9-' < /dev/urandom | head -c 16
}

is_uint() {
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
}

is_port() {
    is_uint "$1" && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

is_decimal() {
    case "$1" in ''|.*|*.|*[!0-9.]*|*.*.*) return 1 ;; esac
}

is_hex() {
    case "$1" in ''|*[!0-9a-fA-F]*) return 1 ;; esac
}

# Replace {{name}} with a value in a rendered file
replace_var() {
    escaped=$(printf '%s' "$3" | sed 's/[&/\]/\\&/g')
    sed -i "s/{{$2}}/$escaped/g" "$1"
}

# Settings from the environment
SERVER_NAME="${ENV_SERVER_NAME:-bf2-docker}"
MAX_PLAYERS="${ENV_MAX_PLAYERS:-16}"
SERVER_PORT="${ENV_SERVER_PORT:-16567}"
GAMESPY_PORT="${ENV_GAMESPY_PORT:-29900}"
INTERNET="${ENV_INTERNET:-1}"
DEMOS_URL="${ENV_DEMOS_URL:-http://example.com/demos/}"
RCON_PASSWORD="${ENV_RCON_PASSWORD:-$(generate_pw)}"
API_KEY="${ENV_API_KEY:-$(generate_pw)}"
BOT_PORT="${ENV_BOT_PORT:-16700}"
TV_AIM_FROM_MISSILE="${ENV_TV_AIM_FROM_MISSILE:-0}"
TV_TURN_BEHIND="${ENV_TV_TURN_BEHIND:-0}"

is_uint "$MAX_PLAYERS" || fail "ENV_MAX_PLAYERS must be a number, got '$MAX_PLAYERS'"
is_port "$SERVER_PORT" || fail "ENV_SERVER_PORT must be a port, got '$SERVER_PORT'"
is_port "$GAMESPY_PORT" || fail "ENV_GAMESPY_PORT must be a port, got '$GAMESPY_PORT'"
case "$INTERNET" in 0|1) ;; *) fail "ENV_INTERNET must be 0 or 1, got '$INTERNET'" ;; esac
is_port "$BOT_PORT" && [ "$BOT_PORT" != 16567 ] || fail "ENV_BOT_PORT must be a port other than 16567, got '$BOT_PORT'"
is_decimal "$TV_AIM_FROM_MISSILE" || fail "ENV_TV_AIM_FROM_MISSILE must be metres (0 or more, e.g. 30 or 7.5), got '$TV_AIM_FROM_MISSILE'"
is_uint "$TV_TURN_BEHIND" || fail "ENV_TV_TURN_BEHIND must be 0 (off) or 1 (on), got '$TV_TURN_BEHIND'"

# The admin channel to BF2WebAdmin: all four variables or none (then the module dials nowhere)
case "${ENV_ADMIN_CONNECT:+c}${ENV_ADMIN_SERVER_ID:+s}${ENV_ADMIN_KEY:+k}${ENV_ADMIN_CERT_SHA256:+p}" in
    '') ADMIN=0 ;;
    cskp) ADMIN=1 ;;
    *) fail 'set all of ENV_ADMIN_CONNECT, ENV_ADMIN_SERVER_ID, ENV_ADMIN_KEY and ENV_ADMIN_CERT_SHA256, or none of them' ;;
esac
if [ "$ADMIN" = 1 ]; then
    case "$ENV_ADMIN_CONNECT" in
        *:*) is_port "${ENV_ADMIN_CONNECT##*:}" && [ "${ENV_ADMIN_CONNECT##*:}" != 16567 ] ||
                 fail "ENV_ADMIN_CONNECT must be <host>:<port>, got '$ENV_ADMIN_CONNECT'" ;;
        *) fail "ENV_ADMIN_CONNECT must be <host>:<port>, got '$ENV_ADMIN_CONNECT'" ;;
    esac
    case "$ENV_ADMIN_SERVER_ID" in
        *[!!-~]*) fail 'ENV_ADMIN_SERVER_ID must be printable ASCII without spaces' ;;
    esac
    [ ${#ENV_ADMIN_SERVER_ID} -le 64 ] || fail 'ENV_ADMIN_SERVER_ID must be at most 64 characters'
    is_hex "$ENV_ADMIN_KEY" && [ $((${#ENV_ADMIN_KEY} % 2)) = 0 ] && [ ${#ENV_ADMIN_KEY} -ge 32 ] && [ ${#ENV_ADMIN_KEY} -le 128 ] ||
        fail 'ENV_ADMIN_KEY must be 32 to 128 hex digits'
    is_hex "$ENV_ADMIN_CERT_SHA256" && [ ${#ENV_ADMIN_CERT_SHA256} = 64 ] ||
        fail 'ENV_ADMIN_CERT_SHA256 must be 64 hex digits (BF2WebAdmin.Server --admin-pin)'
fi

# The server files come from the image. A volume on $SRV would keep the files of an older image
if grep -q " $SRV " /proc/self/mountinfo || [ ! -x "$SRV/bin/amd-64/bf2" ]; then
    fail "$SRV is a mount or has no server. The server files come from the image: mount only /volume, not $SRV"
fi

# Persisted state in /volume
echo 'Linking the persisted state in /volume...'
mkdir -p "$VOLUME/settings" "$VOLUME/demos/pending" "$VOLUME/demos/uploaded" "$VOLUME/logs"
chmod 777 "$VOLUME" "$VOLUME/settings" "$VOLUME/demos" "$VOLUME/demos/pending" "$VOLUME/demos/uploaded" "$VOLUME/logs"
# bf2tool.php (www-data) reads and writes the ban lists too. The server would create banlist.con readable by bf2 only
if [ ! -e "$VOLUME/settings/banlist.con" ]; then
    install -o bf2 -g bf2 -m 666 /dev/null "$VOLUME/settings/banlist.con"
fi
for file in banlist.con mm_bans.xml; do
    if [ -f "$VOLUME/settings/$file" ]; then
        chmod 666 "$VOLUME/settings/$file"
    fi
done
for file in bf2.log modmanager.log; do
    if [ -f "$VOLUME/$file" ]; then
        mv -f "$VOLUME/$file" "$VOLUME/$file.1"
    fi
    install -m 666 /dev/null "$VOLUME/$file"
done
rm -rf "$SETTINGS/banlist.con" "$SETTINGS/mm_bans.xml" "$SRV/mods/bf2/demos" "$SRV/logs" "$SRV/bf2.log" "$SRV/modmanager.log"
ln -s "$VOLUME/settings/banlist.con" "$SETTINGS/banlist.con"
ln -s "$VOLUME/settings/mm_bans.xml" "$SETTINGS/mm_bans.xml"
ln -s "$VOLUME/demos/pending" "$SRV/mods/bf2/demos"
ln -s "$VOLUME/logs" "$SRV/logs"
ln -s "$VOLUME/bf2.log" "$SRV/bf2.log"
ln -s "$VOLUME/modmanager.log" "$SRV/modmanager.log"

# Render the settings from the templates and the environment
echo 'Rendering the settings...'
for file in mods/bf2/openbf2.con mods/bf2/settings/maplist.con mods/bf2/settings/modmanager.con mods/bf2/settings/serversettings.con; do
    install -o bf2 -g bf2 -m 666 "$TEMPLATES/$file" "$SRV/$file"
done
install -o bf2 -g bf2 -m 644 "$TEMPLATES/www/bf2tool.php" "$WWW/bf2tool.php"
replace_var "$SETTINGS/serversettings.con" server_name "$SERVER_NAME"
replace_var "$SETTINGS/serversettings.con" max_players "$MAX_PLAYERS"
replace_var "$SETTINGS/serversettings.con" server_port "$SERVER_PORT"
replace_var "$SETTINGS/serversettings.con" gamespy_port "$GAMESPY_PORT"
replace_var "$SETTINGS/serversettings.con" internet "$INTERNET"
replace_var "$SETTINGS/serversettings.con" demos_url "$DEMOS_URL"
replace_var "$SETTINGS/modmanager.con" rcon_password "$RCON_PASSWORD"
replace_var "$SRV/mods/bf2/openbf2.con" tv_aim_from_missile "$TV_AIM_FROM_MISSILE"
replace_var "$SRV/mods/bf2/openbf2.con" tv_turn_behind "$TV_TURN_BEHIND"
replace_var "$WWW/bf2tool.php" api_key "$API_KEY"
if grep -l '{{' "$SRV/mods/bf2/openbf2.con" "$SETTINGS/maplist.con" "$SETTINGS/modmanager.con" "$SETTINGS/serversettings.con" "$WWW/bf2tool.php"; then
    fail 'placeholders left in the files above'
fi

# bf2tool.php reads and writes the settings in /volume/settings. The rendered ones are links into the server
# (changes through bf2tool.php last until the next start), the ban lists are the persisted files
for file in maplist.con modmanager.con serversettings.con; do
    if [ -f "$VOLUME/settings/$file" ] && [ ! -L "$VOLUME/settings/$file" ]; then
        # Left by an image that kept all settings in /volume, the image is the source now
        mv -f "$VOLUME/settings/$file" "$VOLUME/settings/$file.old"
    fi
    ln -sfn "$SETTINGS/$file" "$VOLUME/settings/$file"
done

# The module's configuration (libserverext.so, loaded from openbf2.con). The bot channel cannot be turned off, so it
# listens on the loopback interface only; never publish it
{
    echo '# Rendered by run.sh on every start from the environment, changes are lost'
    echo "botListen 127.0.0.1:$BOT_PORT"
    echo 'stepMode 0'
    echo 'allowTeleport 0'
    echo 'allowRoundRestart 0'
    echo 'adminAllowConsole 1'
    if [ "$ADMIN" = 1 ]; then
        echo "adminConnect $ENV_ADMIN_CONNECT"
        echo "adminServerId $ENV_ADMIN_SERVER_ID"
        echo "adminKey $ENV_ADMIN_KEY"
        echo "adminCertSha256 $ENV_ADMIN_CERT_SHA256"
    fi
} > "$SRV/serverext.cfg"
chown bf2:bf2 "$SRV/serverext.cfg"
chmod 600 "$SRV/serverext.cfg"

echo "Server '$SERVER_NAME': game port $SERVER_PORT/udp, query port $GAMESPY_PORT/udp, internet $INTERNET, $MAX_PLAYERS players, demos $DEMOS_URL"
if [ -z "$ENV_RCON_PASSWORD" ]; then
    echo "RCON password (random, ENV_RCON_PASSWORD is not set): $RCON_PASSWORD"
fi
if [ -z "$ENV_API_KEY" ]; then
    echo "bf2tool.php API key (random, ENV_API_KEY is not set): $API_KEY"
fi
if [ "$ADMIN" = 1 ]; then
    echo "Admin channel: dials $ENV_ADMIN_CONNECT as $ENV_ADMIN_SERVER_ID"
else
    echo 'Admin channel: off (no ENV_ADMIN_* variables)'
fi
echo "OpenBF2: tv-aim-from-missile $TV_AIM_FROM_MISSILE, tv-turn-behind $TV_TURN_BEHIND, bot channel 127.0.0.1:$BOT_PORT"
sed -n 's/^\(openbf2\|module\|bf2hub\) /Built from \1 /p' "$SRV/openbf2-source.txt"

# Start nginx and php
service nginx start
service php8.4-fpm start

# Start Battlefield 2 server as the bf2 user
# start.sh instead of start_bf2hub.sh, OpenBF2 loads its own libbf2hub.so from mods/bf2/openbf2.con
echo "Starting Battlefield 2 server..."
export TERM=xterm
su -c "cd $SRV && ./start.sh >bf2.log" - bf2

exit 0
