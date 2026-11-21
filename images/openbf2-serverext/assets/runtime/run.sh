#!/bin/sh
# Starts the server. This script is the same in every OpenBF2 image (tests/static/check.py checks that).
#
# Runs on every container start, so a new image or a changed environment variable always takes effect: the server
# files come from the image, the settings are rendered from the templates in /home/bf2/templates and the environment,
# and only the state below is kept in /volume (mount it to keep the state; nothing else needs a mount, and
# /home/bf2/srv must not be mounted):
#   /volume/settings/banlist.con     BF2's ban list
#   /volume/demos/pending            demos being recorded (mods/bf2/demos)
#   /volume/demos/uploaded           finished demos, served by nginx at /demos/ (rotate_demo.py keeps 50)
#   /volume/bf2.log                  the server console of this start (bf2.log.1: the previous start)
#   /volume/logs                     module logs (logs/bf2hub)
# Optional, read but never written:
#   /volume/templates/serversettings.con, /volume/templates/maplist.con
#                                    used instead of the image's templates, to change settings without a new image
set -e

SRV='/home/bf2/srv'
SETTINGS="$SRV/mods/bf2/settings"
TEMPLATES='/home/bf2/templates'
VOLUME='/volume'

fail() {
    echo "run.sh: $*" >&2
    exit 1
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

# The template of a settings file: the one in /volume/templates if there is one, otherwise the image's
template() {
    if [ -f "$VOLUME/templates/$1" ]; then
        echo "$VOLUME/templates/$1"
    else
        echo "$TEMPLATES/mods/bf2/settings/$1"
    fi
}

# An image's own default for a variable: a line "rem default <variable>=<value>" in its serversettings.con template
# (run.sh leaves these lines out of the rendered file)
template_default() {
    tr -d '\r' < "$SERVERSETTINGS_TEMPLATE" | sed -n "s/^rem default $1=//p" | head -n 1
}

SERVERSETTINGS_TEMPLATE=$(template serversettings.con)
MAPLIST_TEMPLATE=$(template maplist.con)

# The server extension (libserverext.so, the admin channel to BF2WebAdmin) is only in the images whose
# mods/bf2/openbf2.con loads it, build.sh removes it from the others
if [ -f "$SRV/bin/amd-64/libserverext.so" ]; then
    SERVEREXT=1
else
    SERVEREXT=0
fi

# Settings from the environment
SERVER_NAME="${ENV_SERVER_NAME:-bf2-docker}"
MAX_PLAYERS="${ENV_MAX_PLAYERS:-16}"
SERVER_PORT="${ENV_SERVER_PORT:-16567}"
GAMESPY_PORT="${ENV_GAMESPY_PORT:-29900}"
INTERNET="${ENV_INTERNET:-1}"
DEMOS_URL="${ENV_DEMOS_URL:-http://example.com/demos/}"
CONTENT_CHECK="${ENV_CONTENT_CHECK:-1}"
BOT_PORT="${ENV_BOT_PORT:-16700}"
TV_AIM_FROM_MISSILE="${ENV_TV_AIM_FROM_MISSILE:-0}"
TV_TURN_BEHIND="${ENV_TV_TURN_BEHIND:-0}"
# Off in retail; an image can turn it on by default (rem default ENV_TV_KEEP_AIM_ON_RELOAD=1)
TV_KEEP_AIM_ON_RELOAD="${ENV_TV_KEEP_AIM_ON_RELOAD:-$(template_default ENV_TV_KEEP_AIM_ON_RELOAD)}"
TV_KEEP_AIM_ON_RELOAD="${TV_KEEP_AIM_ON_RELOAD:-0}"
TV_INPUT_QUEUE="${ENV_TV_INPUT_QUEUE:-0}"
TV_TRACE="${ENV_TV_TRACE:-0}"
# sponsortext variables (https://github.com/cetteup/sponsortext) after the description in sv.sponsorText, read by
# server browsers from the GameSpy query. Unset: the image's default, if it has one; set but empty: none
SPONSOR_VARS="${ENV_SPONSOR_VARS-$(template_default ENV_SPONSOR_VARS)}"
# The password of the stock admin script's RCON, which only an image with sv.adminScript "default" has
RCON_PASSWORD="${ENV_RCON_PASSWORD:-}"
ADMIN_SCRIPT=$(tr -d '\r' < "$SERVERSETTINGS_TEMPLATE" |
    sed -n 's/^[[:space:]]*sv\.adminScript[[:space:]]\{1,\}"\{0,1\}\([^"[:space:]]*\).*/\1/Ip' | tail -n 1)

is_uint "$MAX_PLAYERS" || fail "ENV_MAX_PLAYERS must be a number, got '$MAX_PLAYERS'"
is_port "$SERVER_PORT" || fail "ENV_SERVER_PORT must be a port, got '$SERVER_PORT'"
is_port "$GAMESPY_PORT" || fail "ENV_GAMESPY_PORT must be a port, got '$GAMESPY_PORT'"
case "$INTERNET" in 0|1) ;; *) fail "ENV_INTERNET must be 0 or 1, got '$INTERNET'" ;; esac
case "$CONTENT_CHECK" in 0|1) ;; *) fail "ENV_CONTENT_CHECK must be 0 or 1, got '$CONTENT_CHECK'" ;; esac
is_decimal "$TV_AIM_FROM_MISSILE" || fail "ENV_TV_AIM_FROM_MISSILE must be metres (0 or more, e.g. 30 or 7.5), got '$TV_AIM_FROM_MISSILE'"
is_uint "$TV_TURN_BEHIND" || fail "ENV_TV_TURN_BEHIND must be 0 (off) or 1 (on), got '$TV_TURN_BEHIND'"
is_uint "$TV_KEEP_AIM_ON_RELOAD" || fail "ENV_TV_KEEP_AIM_ON_RELOAD must be 0 (off) or 1 (on), got '$TV_KEEP_AIM_ON_RELOAD'"
case "$TV_INPUT_QUEUE" in [0-8]) ;; *) fail "ENV_TV_INPUT_QUEUE must be 0 (off) to 8, got '$TV_INPUT_QUEUE'" ;; esac
case "$TV_TRACE" in 0|1) ;; *) fail "ENV_TV_TRACE must be 0 or 1, got '$TV_TRACE'" ;; esac
case "$SPONSOR_VARS" in *'"'*|*'
'*) fail 'ENV_SPONSOR_VARS must not contain double quotes or line breaks' ;; esac

# The stock admin script (admin/default.py) reads its RCON password from admin/default.cfg, as "password=<value>".
# Another admin script has no RCON, and the variable is left over from an image that had one
RCON=0
if [ -n "$RCON_PASSWORD" ]; then
    if [ "$ADMIN_SCRIPT" = default ]; then
        case "$RCON_PASSWORD" in
            *[!!-~]*|*=*) fail 'ENV_RCON_PASSWORD must be printable ASCII without spaces or =' ;;
        esac
        RCON=1
    else
        echo "ENV_RCON_PASSWORD is ignored: the admin script '$ADMIN_SCRIPT' has no RCON"
    fi
fi

# The admin channel to BF2WebAdmin: all four variables or none (then the module dials nowhere)
case "${ENV_ADMIN_CONNECT:+c}${ENV_ADMIN_SERVER_ID:+s}${ENV_ADMIN_KEY:+k}${ENV_ADMIN_CERT_SHA256:+p}" in
    '') ADMIN=0 ;;
    cskp) ADMIN=1 ;;
    *) fail 'set all of ENV_ADMIN_CONNECT, ENV_ADMIN_SERVER_ID, ENV_ADMIN_KEY and ENV_ADMIN_CERT_SHA256, or none of them' ;;
esac
if [ "$ADMIN" = 1 ] && [ "$SERVEREXT" = 0 ]; then
    fail 'the ENV_ADMIN_* variables are set, but this image has no server extension (libserverext.so). Use an image that loads it, like openbf2-serverext'
fi
if [ "$SERVEREXT" = 1 ]; then
    is_port "$BOT_PORT" && [ "$BOT_PORT" != 16567 ] || fail "ENV_BOT_PORT must be a port other than 16567, got '$BOT_PORT'"
fi
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
# The server (bf2) writes the ban list. An older image let bf2tool.php (www-data) write it too
if [ ! -e "$VOLUME/settings/banlist.con" ]; then
    install -o bf2 -g bf2 -m 644 /dev/null "$VOLUME/settings/banlist.con"
fi
if [ -f "$VOLUME/settings/banlist.con" ]; then
    chown bf2:bf2 "$VOLUME/settings/banlist.con"
fi
if [ -f "$VOLUME/bf2.log" ]; then
    mv -f "$VOLUME/bf2.log" "$VOLUME/bf2.log.1"
fi
install -m 666 /dev/null "$VOLUME/bf2.log"
rm -rf "$SETTINGS/banlist.con" "$SRV/mods/bf2/demos" "$SRV/logs" "$SRV/bf2.log"
ln -s "$VOLUME/settings/banlist.con" "$SETTINGS/banlist.con"
ln -s "$VOLUME/demos/pending" "$SRV/mods/bf2/demos"
ln -s "$VOLUME/logs" "$SRV/logs"
ln -s "$VOLUME/bf2.log" "$SRV/bf2.log"

# Render the settings from the templates and the environment
echo 'Rendering the settings...'
for file in "$SERVERSETTINGS_TEMPLATE" "$MAPLIST_TEMPLATE"; do
    case "$file" in "$VOLUME"/*) echo "Using $file instead of the image's template" ;; esac
done
install -o bf2 -g bf2 -m 666 "$TEMPLATES/mods/bf2/openbf2.con" "$SRV/mods/bf2/openbf2.con"
install -o bf2 -g bf2 -m 666 "$MAPLIST_TEMPLATE" "$SETTINGS/maplist.con"
install -o bf2 -g bf2 -m 666 "$SERVERSETTINGS_TEMPLATE" "$SETTINGS/serversettings.con"
sed -i '/^rem default /d' "$SETTINGS/serversettings.con"
replace_var "$SETTINGS/serversettings.con" server_name "$SERVER_NAME"
replace_var "$SETTINGS/serversettings.con" max_players "$MAX_PLAYERS"
replace_var "$SETTINGS/serversettings.con" server_port "$SERVER_PORT"
replace_var "$SETTINGS/serversettings.con" gamespy_port "$GAMESPY_PORT"
replace_var "$SETTINGS/serversettings.con" internet "$INTERNET"
replace_var "$SETTINGS/serversettings.con" demos_url "$DEMOS_URL"
replace_var "$SETTINGS/serversettings.con" sponsor_vars "${SPONSOR_VARS:+ \$vars:$SPONSOR_VARS\$}"
replace_var "$SRV/mods/bf2/openbf2.con" tv_aim_from_missile "$TV_AIM_FROM_MISSILE"
replace_var "$SRV/mods/bf2/openbf2.con" tv_turn_behind "$TV_TURN_BEHIND"
replace_var "$SRV/mods/bf2/openbf2.con" tv_keep_aim_on_reload "$TV_KEEP_AIM_ON_RELOAD"
replace_var "$SRV/mods/bf2/openbf2.con" tv_input_queue "$TV_INPUT_QUEUE"
if grep -l '{{' "$SRV/mods/bf2/openbf2.con" "$SETTINGS/maplist.con" "$SETTINGS/serversettings.con"; then
    fail 'placeholders left in the files above'
fi

# The rendered settings are not kept in /volume, the image is the source (modmanager.con is from the images with
# ModManager, before admin/netsky.py)
for file in maplist.con modmanager.con serversettings.con; do
    if [ -L "$VOLUME/settings/$file" ]; then
        # A link to the rendered file, made by an older image for bf2tool.php
        rm -f "$VOLUME/settings/$file"
    elif [ -f "$VOLUME/settings/$file" ]; then
        # Left by an image that kept all settings in /volume
        mv -f "$VOLUME/settings/$file" "$VOLUME/settings/$file.old"
    fi
done

# The content check: with the four fingerprint files in mods/bf2 the server compares the checksums a client reports
# of its game archives, on maps that have an archive.md5, and kicks a client with modified files. Without them it
# checks nothing (a "nocheck" server, where players can use modified game files)
if [ "$CONTENT_CHECK" = 0 ]; then
    for file in std_archive.md5 std_archive_mod.md5 bst_archive.md5 bst_archive_mod.md5; do
        rm -f "$SRV/mods/bf2/$file"
    done
fi

# The stock admin script's RCON: 4711/tcp, and "rcon login <password>" in the game's console. The script listens on
# the port without a password too, but then nobody can log in
if [ "$RCON" = 1 ]; then
    printf 'port=4711\npassword=%s\n' "$RCON_PASSWORD" > "$SRV/admin/default.cfg"
    chown bf2:bf2 "$SRV/admin/default.cfg"
    chmod 600 "$SRV/admin/default.cfg"
fi

# The module's configuration (libserverext.so, loaded from openbf2.con). The bot channel cannot be turned off, so it
# listens on the loopback interface only; never publish it
if [ "$SERVEREXT" = 1 ]; then
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
fi

echo "Server '$SERVER_NAME': game port $SERVER_PORT/udp, query port $GAMESPY_PORT/udp, internet $INTERNET, $MAX_PLAYERS players, content check $CONTENT_CHECK, demos $DEMOS_URL"
echo "OpenBF2: tv-aim-from-missile $TV_AIM_FROM_MISSILE, tv-turn-behind $TV_TURN_BEHIND, tv-keep-aim-on-reload $TV_KEEP_AIM_ON_RELOAD, tv-input-queue $TV_INPUT_QUEUE"
if [ "$RCON" = 1 ]; then
    echo 'RCON: on, 4711/tcp (the stock admin script)'
elif [ "$ADMIN_SCRIPT" = default ]; then
    echo 'RCON: no password (ENV_RCON_PASSWORD), nobody can log in'
fi
if [ "$SERVEREXT" = 0 ]; then
    echo 'Server extension: not in this image'
    sed -n 's/^\(openbf2\|bf2hub\) /Built from \1 /p' "$SRV/openbf2-source.txt"
else
    if [ "$ADMIN" = 1 ]; then
        echo "Server extension: admin channel dials $ENV_ADMIN_CONNECT as $ENV_ADMIN_SERVER_ID, bot channel 127.0.0.1:$BOT_PORT"
    else
        echo "Server extension: admin channel off (no ENV_ADMIN_* variables), bot channel 127.0.0.1:$BOT_PORT"
    fi
    sed -n 's/^\(openbf2\|module\|bf2hub\) /Built from \1 /p' "$SRV/openbf2-source.txt"
fi

# Start nginx, it serves the demos
service nginx start

# Start Battlefield 2 server as the bf2 user
# start.sh instead of start_bf2hub.sh, OpenBF2 loads its own libbf2hub.so from mods/bf2/openbf2.con
# The TV missile trace is a diagnostic that OpenBF2 switches on from its environment, once, when it starts. "su -"
# gives the server a new environment, so the two variables go into its command line. The trace holds 32768 rows per
# start and is appended to /volume/tv-trace.log
TRACE=''
if [ "$TV_TRACE" = 1 ]; then
    TRACE="BF2_TRACE_TV_MISSILES=1 BF2_TV_MISSILE_TRACE_FILE=$VOLUME/tv-trace.log "
    echo "TV missile trace: on, $VOLUME/tv-trace.log (ENV_TV_TRACE)"
fi
echo "Starting Battlefield 2 server..."
export TERM=xterm
su -c "cd $SRV && $TRACE./start.sh >bf2.log" - bf2

exit 0
