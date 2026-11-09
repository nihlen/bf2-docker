"""
Starts a built image and checks that the server comes up and works.

Usage: python tests/smoke/smoke.py <image folder> <docker image tag>

Checks, depending on what the image contains:
- the bf2 process starts and the game port is open
- OpenBF2 loads the modules listed in mods/bf2/openbf2.con
- the image's own admin script (sv.adminScript, admin/<name>.py) loads without errors
- with ModManager: RCON login works, the server name is set from ENV_SERVER_NAME,
  and the maps in maplist.con and the modules in modmanager.con are loaded
- with an admin script instead of ModManager: nothing listens on the RCON port, and the GameSpy query reports
  the server name from ENV_SERVER_NAME, the sponsortext variables and the first map in maplist.con
- the demo hook moves a demo to the web server, where it is listed and downloadable
- bf2tool.php returns the settings with the API key and refuses without it
- the container keeps running
"""

import hashlib
import os
import re
import secrets
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

SRV = "/home/bf2/srv"
GAME_PORT = 16567
QUERY_PORT = 29900
RCON_PORT = 4711
STARTUP_TIMEOUT = 300
SERVER_NAME = "bf2-docker smoke test"
SPONSOR_VARS = "$vars:website=https://bf2.nihlen.net/;discord=https://discord.gg/DPaJaMKAc3;provider=bf2hub.com$"
# What OpenBF2 writes when an admin script fails to load, or its update() fails
ADMIN_ERRORS = r"admin: (failed to import|\S+: you must provide the functions|\S+: init function failed)|error: admin update failed"


class SmokeTestError(Exception):
    pass


def docker(*args, check=True):
    result = subprocess.run(["docker", *args], capture_output=True, text=True)
    if check and result.returncode != 0:
        raise SmokeTestError("docker %s failed: %s" % (args[0], result.stderr.strip()))
    return result.stdout


def wait_for(description, condition, container, timeout=STARTUP_TIMEOUT):
    """Wait until condition() returns a truthy value, failing early if the container stops."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        result = condition()
        if result:
            return result
        if docker("inspect", "-f", "{{.State.Running}}", container).strip() != "true":
            raise SmokeTestError("container stopped while waiting for %s" % description)
        time.sleep(2)
    raise SmokeTestError("timed out after %ds waiting for %s" % (timeout, description))


def container_exec(container, command):
    return docker("exec", container, "sh", "-c", command, check=False)


def bf2_running(container):
    # procps is not installed in every image, so look for the process in /proc
    return "bf2" in container_exec(container, "cat /proc/[0-9]*/comm 2>/dev/null").split()


def udp_port_open(container, port):
    # /proc/net/udp lists local addresses as <hex ip>:<hex port>
    return (":%04X " % port) in container_exec(container, "cat /proc/net/udp /proc/net/udp6 2>/dev/null")


def tcp_port_listening(container, port):
    # /proc/net/tcp lists local addresses as <hex ip>:<hex port>, state 0A is LISTEN
    for line in container_exec(container, "cat /proc/net/tcp /proc/net/tcp6 2>/dev/null").splitlines():
        fields = line.split()
        if len(fields) > 3 and fields[1].endswith(":%04X" % port) and fields[3] == "0A":
            return True
    return False


def host_port(container, port, protocol="tcp"):
    address = docker("port", container, "%d/%s" % (port, protocol)).splitlines()[0]
    host, _, mapped = address.rpartition(":")
    return host, int(mapped)


class Rcon:
    """ModManager RCON client. Commands prefixed with 0x02 get replies ending with 0x04."""

    def __init__(self, address, password):
        self.sock = socket.create_connection(address, timeout=10)
        self.buffer = b""
        seed = self.read_match(rb"### Digest seed: (\S+)\n").group(1)
        digest = hashlib.md5(seed + password.encode()).hexdigest()
        reply = self.command("login %s" % digest)
        if "Authentication successful" not in reply:
            raise SmokeTestError("RCON login failed: %s" % reply.strip())

    def read_match(self, pattern):
        """Read until pattern matches and remove everything up to the end of the match from the buffer."""
        while True:
            match = re.search(pattern, self.buffer)
            if match:
                self.buffer = self.buffer[match.end():]
                return match
            data = self.sock.recv(4096)
            if not data:
                raise SmokeTestError("RCON connection closed")
            self.buffer += data

    def command(self, cmd):
        self.sock.sendall(b"\x02" + cmd.encode() + b"\n")
        return self.read_match(rb"([^\x04]*)\x04").group(1).decode(errors="replace")

    def close(self):
        self.sock.close()


def gamespy_query(address):
    """The server keys from the GameSpy (v3) query port, or None if it doesn't answer."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(3)
    try:
        # 0xFE 0xFD, type 0 (query), a 4 byte id, then: all server keys, no players, no teams
        sock.sendto(b"\xfe\xfd\x00smok\xff\x00\x00", address)
        data = sock.recv(65535)
    except OSError:
        return None
    finally:
        sock.close()
    if not data.startswith(b"\x00smok"):
        return None
    fields = data[5:].decode("utf-8", errors="replace").split("\x00")
    return dict(zip(fields[0::2], fields[1::2]))


def connect_rcon(address, password):
    try:
        return Rcon(address, password)
    except (OSError, SmokeTestError):
        return None


def http_get(address, path):
    url = "http://%s:%d%s" % (address[0], address[1], path)
    try:
        with urllib.request.urlopen(url, timeout=10) as response:
            return response.status, response.read().decode(errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")
    except OSError:
        return None, ""


def config_values(container, path, pattern):
    return re.findall(pattern, container_exec(container, "cat %s" % path), re.IGNORECASE | re.MULTILINE)


def check(results, name, ok, detail=""):
    results.append((name, ok, detail))
    print("%s %s%s" % ("ok  " if ok else "FAIL", name, ": " + detail if detail and not ok else ""))


def run_checks(image, container, rcon_password, api_key):
    results = []
    build = os.path.join(image, "assets", "build")
    runtime = os.path.join(image, "assets", "runtime")
    with open(os.path.join(build, "assets.txt"), encoding="utf-8") as f:
        has_modmanager = "ModManager" in f.read()
    settings = os.path.join(build, "bf2", "mods", "bf2", "settings", "serversettings.con")
    settings_text = open(settings, encoding="utf-8").read() if os.path.isfile(settings) else ""
    has_sponsor_vars = "{{sponsor_vars}}" in settings_text
    # The image's own admin script, admin/<name>.py (not ModManager's, which comes from its zip)
    match = re.search(r'^\s*sv\.adminScript\s+"?(\w+)', settings_text, re.IGNORECASE | re.MULTILINE)
    admin_script = match.group(1) if match and os.path.isfile(os.path.join(build, "bf2", "admin", match.group(1) + ".py")) else None
    has_nginx = os.path.isdir(os.path.join(runtime, "nginx"))
    has_bf2tool = os.path.isfile(os.path.join(runtime, "www", "bf2tool.php"))
    has_demo_hook = os.path.isfile(os.path.join(build, "bf2", "adminutils", "demo", "rotate_demo.py"))

    wait_for("the bf2 process", lambda: bf2_running(container), container)
    check(results, "bf2 process started", True)

    wait_for("game port %d" % GAME_PORT, lambda: udp_port_open(container, GAME_PORT), container)
    check(results, "game port %d open" % GAME_PORT, True)

    # OpenBF2 reports every module it loads from mods/bf2/openbf2.con on the console
    openbf2_con = os.path.join(build, "bf2", "mods", "bf2", "openbf2.con")
    if os.path.isfile(openbf2_con):
        with open(openbf2_con, encoding="utf-8") as f:
            modules = re.findall(r'^\s*openbf2\.addModDll\s+"?(\w+)', f.read(), re.IGNORECASE | re.MULTILINE)
        console = container_exec(container, "cat %s/bf2.log" % SRV)
        for module in modules:
            loaded = re.search(r"openbf2\.addModDll: loaded '[^']*%s[^']*'" % re.escape(module), console)
            error = re.search(r"openbf2\.addModDll: (could not load|initDll refused) '[^']*%s[^']*" % re.escape(module), console)
            check(results, "OpenBF2 loaded module %s" % module, bool(loaded),
                  error.group(0) if error else "no load message on the console")

    # The admin script writes "<name>: admin script loaded" to the console at the end of init(), and
    # "<name>: <handler> failed: <traceback>" if one of its handlers fails
    if admin_script:
        loaded_line = "%s: admin script loaded" % admin_script
        console = lambda: container_exec(container, "cat %s/bf2.log" % SRV)
        wait_for("the admin script", lambda: loaded_line in console(), container, timeout=60)
        check(results, "admin script %s loaded" % admin_script, True)
        error = re.search(r"(%s|%s: \w+ failed: ).*" % (ADMIN_ERRORS, re.escape(admin_script)), console())
        check(results, "no admin script errors on the console", not error, error.group(0)[:200] if error else "")

    if has_modmanager:
        rcon = wait_for("RCON login", lambda: connect_rcon(host_port(container, 4711), rcon_password), container)
        check(results, "RCON login", True)

        name = rcon.command("exec sv.serverName").strip()
        check(results, "server name set from ENV_SERVER_NAME", name == SERVER_NAME, "got '%s'" % name)

        maplist = rcon.command("exec maplist.list")
        expected_maps = config_values(container, SRV + "/mods/bf2/settings/maplist.con", r"^\s*maplist\.append\s+(\S+)")
        missing = [m for m in expected_maps if '"%s"' % m not in maplist and " %s " % m not in maplist]
        check(results, "%d maps in maplist" % len(expected_maps), bool(expected_maps) and not missing,
              "missing %s" % ", ".join(missing) if missing else "maplist.con is empty")

        modules = rcon.command("mm listModules")
        expected_modules = config_values(container, SRV + "/mods/bf2/settings/modmanager.con", r'^\s*modmanager\.loadModule\s+"?(\w+)')
        missing = [m for m in expected_modules if m not in modules]
        check(results, "%d ModManager modules loaded" % len(expected_modules), not missing, "missing %s" % ", ".join(missing))
        rcon.close()
    elif admin_script:
        # The image's admin script instead of ModManager, so no RCON: the settings are checked through the GameSpy
        # query, which server browsers read
        check(results, "nothing listens on the RCON port %d" % RCON_PORT, not tcp_port_listening(container, RCON_PORT))

        query = wait_for("the GameSpy query", lambda: gamespy_query(host_port(container, QUERY_PORT, "udp")), container, timeout=60)
        check(results, "GameSpy query answers", True)
        hostname = query.get("hostname")
        check(results, "server name set from ENV_SERVER_NAME", hostname == SERVER_NAME, "got '%s'" % hostname)

        # sponsortext variables in sv.sponsorText (netsky-openbf2-*): the $ and ; must survive the settings file
        if has_sponsor_vars:
            sponsor = query.get("bf2_sponsortext", "")
            check(results, "sponsortext variables in sv.sponsorText", sponsor.endswith(" " + SPONSOR_VARS), "got '%s'" % sponsor)

        # The server starts with the first map in maplist.con. The query has the map's name with spaces (dalian plant)
        maps = config_values(container, SRV + "/mods/bf2/settings/maplist.con", r"^\s*maplist\.append\s+(\S+)\s+(\S+)")
        expected = " ".join(maps[0]).lower() if maps else "a map in maplist.con"
        running = ("%s %s" % (query.get("mapname", "").replace(" ", "_"), query.get("gametype", ""))).lower()
        check(results, "first map in maplist.con running", running == expected, "got '%s', expected '%s'" % (running, expected))

    if has_nginx:
        web = host_port(container, 80)
        status = wait_for("nginx", lambda: http_get(web, "/demos/")[0], container, timeout=60)
        check(results, "nginx lists demos", status == 200, "status %s" % status)

        if has_demo_hook:
            # Run the hook like the server does at the end of a round: system(3) as the bf2 user
            demo = "smoke_test.bf2demo"
            output = docker("exec", "-u", "bf2", container, "sh", "-c",
                            'cd %s && touch mods/bf2/demos/%s && adminutils/demo/rotate_demo.py "%s/mods/bf2/demos/%s" 2>&1; echo "exit=$?"'
                            % (SRV, demo, SRV, demo), check=False).strip()
            check(results, "demo hook runs", output.endswith("exit=0"), output.replace("\n", " ")[-120:])

            status, listing = http_get(web, "/demos/")
            check(results, "demo listed in /demos/", demo in listing, "status %s, '%s'" % (status, listing[:80]))
            status, _ = http_get(web, "/" + demo)
            check(results, "demo downloadable", status == 200, "status %s" % status)

        if has_bf2tool:
            status, _ = http_get(web, "/bf2tool.php?key=wrong&getsettings=maplist.con")
            check(results, "bf2tool.php refuses a wrong key", status == 403, "status %s" % status)

            status, body = http_get(web, "/bf2tool.php?key=%s&getsettings=maplist.con" % api_key)
            settings = container_exec(container, "cat /volume/settings/maplist.con")
            same = body.replace("\r\n", "\n").strip() == settings.replace("\r\n", "\n").strip()
            check(results, "bf2tool.php returns settings", status == 200 and same,
                  "status %s, body '%s'" % (status, body.strip()[:80]))

    time.sleep(5)
    check(results, "container still running", docker("inspect", "-f", "{{.State.Running}}", container).strip() == "true")
    return results


def main(image, tag):
    name = "bf2-docker-smoke-" + os.path.basename(os.path.normpath(image))
    rcon_password, api_key = secrets.token_hex(8), secrets.token_hex(8)
    docker("rm", "-f", name, check=False)
    docker("run", "-d", "--name", name,
           "-e", "ENV_SERVER_NAME=" + SERVER_NAME,
           "-e", "ENV_RCON_PASSWORD=" + rcon_password,
           "-e", "ENV_BF2CCD_PASSWORD=" + secrets.token_hex(8),
           "-e", "ENV_API_KEY=" + api_key,
           "-p", "127.0.0.1::%d/tcp" % RCON_PORT, "-p", "127.0.0.1::80/tcp", "-p", "127.0.0.1::%d/udp" % QUERY_PORT,
           tag)
    try:
        results = run_checks(image, name, rcon_password, api_key)
        failed = [r for r in results if not r[1]]
    except SmokeTestError as e:
        print("FAIL %s" % e)
        failed = [e]
    if failed:
        print("--- container log (last 30 lines)")
        print(docker("logs", "--tail", "30", name, check=False))
    docker("rm", "-f", name, check=False)
    return 1 if failed else 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip())
    sys.exit(main(sys.argv[1], sys.argv[2]))
