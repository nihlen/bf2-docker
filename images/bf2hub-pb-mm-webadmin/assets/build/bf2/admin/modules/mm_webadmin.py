"""
WebAdmin Module
======================
Send and receive messages from a master server to extend functionality 
of the Battlefield 2 server and simplify external communication.

This base module registers the game event handlers, timers and sets up a 
socket connection server

======= Author =======
https://bf2.nihlen.net

====== Based on ======
mm_sample.py    by Steven 'Killing' Hartland
bf2bot.py       by DeadEd
"""

import bf2
import host
import socket
import math
import re
import errno
import mm_utils
# import mm_rcon
from bf2.stats.constants import *

#
# Module information
#
__version__ = 0.5
__description__ = "WebAdmin v%s" % __version__
__required_modules__ = {'modmanager': 1.6}
__supports_reload__ = True  # Does this module support reload (are all its reference closed on shutdown?)
__supported_games__ = {'bf2': True, 'bf2142': False}

configDefaults = {
    #
    # Web Admin settings
    #
    'serverHost': 'host.docker.internal',  # master server host
    'serverPort': 4300,  # master server port
    'timerInterval': 0.25,  # fast timer interval in seconds
}

#
# Debug output in the server console
#
IS_DEBUG = False

#
# Ticket timer
#
TICKET_STATUS_TIMER = None  # Timer object
TICKET_STATUS_DELAY = 60  # Timer delay

#
# WebAdmin Class
#


class WebAdmin(object):

    def __init__(self, modManager):
        """Provides static initialisation."""

        self.mm = modManager
        self.__state = 0

        # Custom RCon Commands
        self.__cmds = {
            'connect': {'method': self.cmdConnect, 'args': '<ip> <port>', 'level': 10},
            'connectprivate': {'method': self.cmdConnectPrivate, 'args': '<port>', 'level': 10}
        }

        # Timers
        self.fastTimer = None

        # Web Admin socket
        self.__socket = None

        # We need updates to receive socket messages
        self.mm.registerUpdates(self.update)

        # All initialisation done
        self.mm.info("ModManager WebAdmin started")

    def openSocket(self):
        """Connect to Server TCP socket."""
        if self.__socket:
            self.closeSocket()

        try:
            # If a docker container name or hostname is given then we need to resolve it to an IPv4 address first
            if not self.valid_ipv4(self.__config['serverHost']):
                resolvedIp = socket.gethostbyname(self.__config['serverHost'])
                self.mm.info("Resolved host name %s to %s" % (self.__config['serverHost'], resolvedIp))
                self.__config['serverHost'] = resolvedIp

            self.__socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.__socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.__socket.settimeout(5)
            self.__socket.connect((self.__config['serverHost'], self.__config['serverPort']))

            # Set non-blocking last, else it will freeze when connecting
            self.__socket.setblocking(0)

            self.outbuffer = OutputBuffer(self.mm, self.__socket, True)  # outgoing buffer
            self.inbuffer = ''  # incoming buffer

            self.mm.info("WebAdmin successfully connected to server socket %s:%s" % (self.__config['serverHost'], self.__config['serverPort']))

            self.onSocketConnected()

        except Exception, detail:
            self.mm.error("WebAdmin failed to connect to server socket %s:%s (%s)" % (self.__config['serverHost'], self.__config['serverPort'], detail), False)
            self.__socket = None

    def closeSocket(self):
        if self.__socket:
            self.__socket.close()
            self.__socket = None
            self.mm.info("WebAdmin socket closed")
            self.onSocketDisconnected()

    def sendMessage(self, message):
        # End with \n so readLine() works on the server, else all messages will stack up until newline is received
        if self.outbuffer:
            self.outbuffer.enqueue(message + "\n")

    def sendEventMessage(self, type, *args):
        self.sendMessage("%s\t%s" % (type, '\t'.join(map(str, args))))

    def sendReconnectMessage(self):
        # self.onGameStatusChange(self.currentGameStatus)
        self.onGameStatusChange(self.mm.currentGameStatus)
        for p in bf2.playerManager.getPlayers():
            self.onPlayerConnect(p)
            self.onPlayerScore(p, 0)
            vehicle = p.getVehicle()
            if vehicle:
                self.onEnterVehicle(p, vehicle)

    def recvMessage(self, message):
        # Only add things that can't be achieved through host.rcon_invoke
        try:
            self.handleCommand(message)
        except Exception, detail:
            self.mm.error("Handle command error: (%s)" % detail, False)

    def handleCommand(self, message):
        """Handle a command"""

        # Run RCon command
        if message.startswith("rcon "):

            rcon = message[len("rcon "):]
            response = host.rcon_invoke(rcon)
            if response[-1] == '\n':
                response = response[:-1]
            self.sendMessage(response.replace('\n', '\b'))  # Use something else than backspace? \t is used by events

        # Rcon command and return with a response code
        elif message.startswith("rconresponse "):

            (code, rcon) = mm_utils.largs(message[len("rconresponse "):], None, 2, '')
            response = host.rcon_invoke(rcon)
            if response[-1] == '\n':
                response = response[:-1]
            self.sendMessage("response\t%s\t%s" % (code, response.replace('\n', '\b')))  # Use something else than backspace? \t is used by events

        # PM a player using the rcon feedback function (message appears in their console)
        elif message.startswith("pm "):
            (playerid, message) = mm_utils.largs(message[len("pm "):], None, 2, '')
            p = mm_utils.find_player(playerid)
            if p:
                host.rcon_feedback(p.index, str(message))

        # Teleport a player
        elif message.startswith("position "):

            (playerid, x, h, y) = mm_utils.largs(message[len("position "):], None, 4, '')
            p = mm_utils.find_player(playerid)
            pos = (float(x), float(h), float(y))
            if p:
                setPlayerPosition(p, pos)

        # Rotate a player
        elif message.startswith("rotation "):

            (playerid, yaw, pitch, roll) = mm_utils.largs(message[len("rotation "):], None, 4, '')
            p = mm_utils.find_player(playerid)
            rot = (float(yaw), float(pitch), float(roll))
            if p:
                setPlayerRotation(p, rot)

        # Set player health (vehicle damage)
        elif message.startswith("damage "):

            (playerid, damage) = mm_utils.largs(message[len("damage "):], None, 2, '')
            p = mm_utils.find_player(playerid)
            if p:
                setPlayerDamage(p, get_int((damage)))

        # Set player rank
        elif message.startswith("rank "):

            (playerid, ranknum, rankevent) = mm_utils.largs(message[len("rank "):], None, 3, '')
            p = mm_utils.find_player(playerid)
            ranknum = get_int(ranknum)
            rankevent = rankevent == '1'
            if p:
                setPlayerRank(p, ranknum, rankevent)

        # Give player a medal award
        elif message.startswith("medal "):

            (playerid, medalnum, medalval) = mm_utils.largs(message[len("medal "):], None, 3, '')
            p = mm_utils.find_player(playerid)
            if p and medalnum and medalval:
                awardPlayer(p, get_int(ranknum), get_int(rankevent))

        # Send game event
        elif message.startswith("gameevent "):

            (playerid, event, data) = mm_utils.largs(message[len("gameevent "):], None, 3, '')
            p = mm_utils.find_player(playerid)
            event = get_int(event)
            data = get_int(data)
            if p and event and data:
                bf2.gameLogic.sendGameEvent(p, event, data)

        # Send HUD event
        elif message.startswith("hudevent "):

            (playerid, event, data) = mm_utils.largs(message[len("hudevent "):], None, 3, '')
            p = mm_utils.find_player(playerid)
            event = get_int(event)
            data = get_int(data)
            if p and event and data:
                bf2.gameLogic.sendHudEvent(p, event, data)

        # Set score
        elif message.startswith("score "):

            (playerid, totalScore, teamScore, kills, deaths) = mm_utils.largs(message[len("score "):], None, 5, '')
            p = mm_utils.find_player(playerid)
            if p:
                p.score.rplScore = int(teamScore)
                p.score.kills = int(kills)
                p.score.deaths = int(deaths)
                p.score.score = int(totalScore)

        # Set team
        elif message.startswith("team "):

            (playerid, teamid) = mm_utils.largs(message[len("team "):], None, 2, '')
            p = mm_utils.find_player(playerid)
            if p:
                p.setTeam(get_int(teamid))
                if p.isAlive():
                    setPlayerDamage(p, 1)
                self.onPlayerChangeTeams(p, False)

        # Set timer interval
        elif message.startswith("timerinterval "):

            interval = message[len("timerinterval "):]
            self.__config['timerInterval'] = float(interval)
            self.stopFastTimer()
            self.startFastTimer(float(self.__config['timerInterval']), (1, 2, 3))

    def cmdExec(self, ctx, cmd):
        """Execute a WebAdmin sub command."""
        return mm_utils.exec_subcmd(self.mm, self.__cmds, ctx, cmd)

    def cmdConnect(self, ctx, cmd):
        global IS_DEBUG

        (ip, port) = mm_utils.largs(cmd, None, 2, '')

        self.__config['serverHost'] = ip
        self.__config['serverPort'] = get_int(port)
        IS_DEBUG = self.__config['serverHost'] == '127.0.0.1'

        # Possible reconnection
        self.openSocket()

        if self.__socket:
            # Send data that the server missed, like player connections, vehicles and stats
            self.sendReconnectMessage()
            ctx.write('Connected successfully to %s:%s' % (ip, port))
        else:
            ctx.write('Connection failed to %s:%s' % (ip, port))

        return 1

    def cmdConnectPrivate(self, ctx, cmd):
        global IS_DEBUG

        ip = ctx.conn.addr[0]
        port = cmd
        self.__config['serverHost'] = ip
        self.__config['serverPort'] = get_int(port)
        IS_DEBUG = self.__config['serverHost'] == '127.0.0.1'

        # Possible reconnection
        self.openSocket()

        if self.__socket:
            # Send data that the server missed, like player connections, vehicles and stats
            self.sendReconnectMessage()
            ctx.write('Connected successfully to %s:%s' % (ip, port))
        else:
            ctx.write('Connection failed to %s:%s' % (ip, port))

        return 1

    def valid_ipv4(self, s):
        a = s.split('.')
        if len(a) != 4:
            return False
        for x in a:
            if not x.isdigit():
                return False
            i = int(x)
            if i < 0 or i > 255:
                return False
        return True

    def shutdown(self):
        """Shutdown and stop processing."""

        # Unregister game handlers and do any other
        # other actions to ensure your module no longer affects
        # the game in anyway
        self.mm.unregisterRconCmdHandler('connect')

        self.closeSocket()
        self.mm.info("ModManager WebAdmin shutdown")

        # Flag as shutdown as there is currently way to:
        # host.unregisterHandler
        self.__state = 2

    def update(self):
        # From mm_rcon.AdminConnection.update
        if 1 != self.__state:
            return 0

        if not self.__socket:
            # socket already closed e.g. DOS protection
            return 0

        # Process incoming requests
        err = None
        try:
            while not err:
                data = self.__socket.recv(1024)
                if data:
                    self.inbuffer += data
                    while not err:
                        nlpos = self.inbuffer.find('\n')
                        if nlpos != -1:
                            self.recvMessage(self.inbuffer[0:nlpos])
                            self.inbuffer = self.inbuffer[nlpos+1:]  # keep rest of buffer
                        else:
                            if len(self.inbuffer) > 128:
                                err = 'data format error: no newline in message'
                            break
                else:
                    err = 'peer disconnected'
                    self.onSocketDisconnected()

                if not self.__socket:
                    # socket already closed e.g. DOS protection
                    return 0

        except socket.error, detail:
            if detail[0] != errno.EWOULDBLOCK:
                err = detail[1]
                if detail[0] != errno.EPIPE and detail[0] != errno.ECONNRESET:
                    # only print error if the client didnt disconnect
                    self.mm.error("webadmin: update failed %s" % detail)

        if not err:
            # Send any output
            err = self.outbuffer.update()

        if err:
            self.mm.error("ERROR: webadmin update: %s" % err)
            self.closeSocket()
            #self.close( err )
            return 0

        return 1

    def init(self):
        """Provides default initialisation."""
        global TICKET_STATUS_TIMER, TICKET_STATUS_DELAY

        # Load the configuration
        self.__config = self.mm.getModuleConfig(configDefaults)

        # Open Web Admin socket
        self.openSocket()

        # Register game handlers and do dynamic initialisation
        if self.__state == 0:

            # Game Status Events
            host.registerGameStatusHandler(self.onGameStatusChange)

            # Game Events
            host.registerHandler('ControlPointChangedOwner', self.onControlPointChangedOwner, 1)

            # Ticket timer (Don't care atm, move timers to server?)
            #TICKET_STATUS_TIMER = bf2.Timer(self.onTicketStatusTimer, TICKET_STATUS_DELAY, 1)
            # TICKET_STATUS_TIMER.setRecurring(TICKET_STATUS_DELAY)

            # Player Events
            host.registerHandler('PlayerConnect', self.onPlayerConnect, 1)
            host.registerHandler('PlayerSpawn', self.onPlayerSpawn, 1)
            host.registerHandler('PlayerScore', self.onPlayerScore, 1)
            host.registerHandler('PlayerChangeTeams', self.onPlayerChangeTeams, 1)
            host.registerHandler('PlayerRevived', self.onPlayerRevived, 1)
            host.registerHandler('PlayerKilled', self.onPlayerKilled, 1)
            host.registerHandler('PlayerDeath', self.onPlayerDeath, 1)
            host.registerHandler('PlayerDisconnect', self.onPlayerDisconnect, 1)

            # Vehicle Events
            host.registerHandler('EnterVehicle', self.onEnterVehicle, 1)
            host.registerHandler('ExitVehicle', self.onExitVehicle, 1)
            host.registerHandler('VehicleDestroyed', self.onVehicleDestroyed, 1)

            # Misc Events
            host.registerHandler('ChatMessage', self.onChatMessage, 1)

            # self.sendMessage("WebAdmin initialised on the BF2 server.")

        # Register our rcon command handlers
        self.mm.registerRconCmdHandler('wa', {'method': self.cmdExec, 'subcmds': self.__cmds, 'level': 1})

        # Update to the running state
        self.__state = 1

    def startFastTimer(self, interval, data):
        if self.__socket and (self.fastTimer is None) and (len(bf2.playerManager.getPlayers()) > 0):
            self.stopFastTimer()
            self.fastTimer = bf2.Timer(self.onFastTimer, interval, 1, data)
            self.fastTimer.setRecurring(interval)

    def stopFastTimer(self):
        if self.fastTimer:
            self.fastTimer.destroy()
            self.fastTimer = None

    #
    # Socket Events
    #
    def onSocketConnected(self):
        servername = host.rcon_invoke('sv.serverName').strip()
        gameport = host.rcon_invoke('sv.serverPort').strip()
        queryport = host.rcon_invoke('sv.gameSpyPort').strip()
        maplist = ",".join(getMapList())
        self.sendEventMessage("serverInfo", servername, maplist, gameport, queryport, host.ss_getParam('maxPlayers'))

    def onSocketDisconnected(self):
        self.stopFastTimer()

    #
    # Game Status Events
    #
    def onGameStatusChange(self, statusChange):
        if self.__state != 1:
            return 0

        #self.currentGameStatus = statusChange
        if statusChange == bf2.GameStatus.Playing:
            self.sendEventMessage("gameStatePlaying", bf2.gameLogic.getTeamName(1), bf2.gameLogic.getTeamName(2), host.sgl_getMapName(), host.ss_getParam('maxPlayers'))
            self.startFastTimer(float(self.__config['timerInterval']), (1, 2, 3))

        elif statusChange == bf2.GameStatus.EndGame:
            self.sendEventMessage("gameStateEndGame", bf2.gameLogic.getTeamName(1), host.sgl_getParam('tickets', 1, 0),
                                  bf2.gameLogic.getTeamName(2), host.sgl_getParam('tickets', 2, 0), host.sgl_getMapName())
        elif statusChange == bf2.GameStatus.PreGame:
            self.sendEventMessage("gameStatePreGame")
        elif statusChange == bf2.GameStatus.Paused:
            self.sendEventMessage("gameStatePaused")
        elif statusChange == bf2.GameStatus.RestartServer:
            self.sendEventMessage("gameStateRestart")
        elif statusChange == bf2.GameStatus.NotConnected:
            self.sendEventMessage("gameStateNotConnected")
        else:
            host.rcon_invoke('echo "unknown status: ' + str(statusChange) + '"')

    #
    # Game Events
    #
    def onControlPointChangedOwner(self, controlPoint, underAttack):
        if 1 != self.__state:
            return 0
        flagPos = controlPoint.cp_getParam('flag')
        owner = controlPoint.cp_getParam('team')
        if flagPos == 1 and underAttack == 1 and owner == 0:
            self.sendEventMessage("controlPointCapture", 1, controlPoint.templateName)
        elif flagPos == 2 and underAttack == 1 and owner == 0:
            self.sendEventMessage("controlPointCapture", 2, controlPoint.templateName)
        elif underAttack == 0 and owner == flagPos:
            self.sendEventMessage("controlPointNeutralised", controlPoint.templateName)

    #
    # Timer Events
    #
    def onTicketStatusTimer(self, data):
        if 1 != self.__state:
            return 0
        if host.pmgr_getNumberOfPlayers() > 0:
            self.sendEventMessage("ticketStatus", bf2.gameLogic.getTeamName(1), host.sgl_getParam('tickets', 1, 0),
                                  bf2.gameLogic.getTeamName(2), host.sgl_getParam('tickets', 2, 0), host.sgl_getMapName())

    def onFastTimer(self, data):
        try:
            # Players
            for player in bf2.playerManager.getPlayers():
                self.onPlayerUpdate(player)

            # Projectiles
            allProjs = bf2.objectManager.getObjectsOfType('dice.hfe.world.ObjectTemplate.GenericProjectile')
            if len(allProjs) > 0:
                for proj in allProjs:
                    if proj.templateName == 'agm114_hellfire_tv':
                        self.onProjectileUpdate(proj)

        except Exception, detail:
            self.sendMessage('ERROR: %s' % detail)
            host.rcon_invoke('echo "%s"' % detail)

    def onPlayerUpdate(self, player):
        # return
        vehicle = player.getVehicle()
        self.sendEventMessage("playerPositionUpdate", player.index, getPositionString(vehicle), getRotationString(vehicle), player.getPing())

    def onProjectileUpdate(self, projectile):
        self.sendEventMessage("projectilePositionUpdate", findId(projectile), projectile.templateName, getPositionString(projectile), getRotationString(projectile))
        if IS_DEBUG:
            host.rcon_invoke('game.sayall "Proj: %s"' % getRotationString(projectile))

    #
    # Player Events
    #
    def onPlayerConnect(self, player):
        if 1 != self.__state:
            return 0
        self.sendEventMessage("playerConnect", player.index, player.getName(), player.getProfileId(), player.getAddress(), mm_utils.get_cd_key_hash(player), player.getTeam())
        self.startFastTimer(float(self.__config['timerInterval']), (1, 2, 3))

    def onPlayerSpawn(self, player, soldier):
        if 1 != self.__state:
            return 0
        self.sendEventMessage("playerSpawn", player.index, getPositionString(soldier), getRotationString(soldier))

    def onPlayerChangeTeams(self, player, humanHasSpawned):
        if 1 != self.__state:
            return 0
        self.sendEventMessage("playerChangeTeam", player.index, player.getTeam())

    def onPlayerScore(self, player, difference):
        if 1 != self.__state:
            return 0
        #self.sendEventMessage("playerScore", player.index, difference)
        self.sendEventMessage("playerScore", player.index, player.score.score, player.score.rplScore, player.score.kills, player.score.deaths)

    def onPlayerRevived(self, revivee, medic):
        if 1 != self.__state:
            return 0
        self.sendEventMessage("playerRevived", medic.index, revivee.index)

    # TODO: crashing in plane/heli doesn't show -DeadEd
    def onPlayerKilled(self, victim, attacker, weapon, assists, victimSoldierObject):
        if 1 != self.__state:
            return 0
        if victim.index == attacker.index:
            self.sendEventMessage("playerKilledSelf", victim.index, getPositionString(victimSoldierObject), )
        elif victim.getTeam() == attacker.getTeam():
            self.sendEventMessage("playerTeamkilled", attacker.index, getPositionString(attacker.getVehicle()), victim.index, getPositionString(victimSoldierObject), )
        elif attacker == None and weapon == None and victimSoldierObject != None:
            # TODO: being run over by a vehicle doesn't show -DeadEd
            if hasattr(attacker, 'lastDrivingPlayerIndex'):
                attacker = bf2.playerManager.getPlayerByIndex(victimSoldierObject.lastDrivingPlayerIndex)
                self.sendEventMessage("playerKilled", attacker.index, getPositionString(attacker.getVehicle()), victim.index, getPositionString(victimSoldierObject), "roadkill")
        else:
            self.sendEventMessage("playerKilled", attacker.index, getPositionString(attacker.getVehicle()), victim.index, getPositionString(victimSoldierObject), weapon.templateName)

    def onPlayerDeath(self, player, soldierObject):
        if 1 != self.__state:
            return 0
        self.sendEventMessage("playerDeath", player.index, getPositionString(soldierObject))

    def onPlayerDisconnect(self, player):
        if 1 != self.__state:
            return 0
        self.sendEventMessage("playerDisconnect", player.index)
        if (len(bf2.playerManager.getPlayers()) < 1):
            self.stopFastTimer()
        host.rcon_invoke('echo "Players: %s" ' % str(len(bf2.playerManager.getPlayers())))

    #
    # Vehicle Events
    #
    def onEnterVehicle(self, player, vehicle, freeSoldier=False):
        if 1 != self.__state:
            return 0
        rootVehicle = bf2.objectManager.getRootParent(vehicle)
        self.sendEventMessage("enterVehicle", player.index, findId(rootVehicle), rootVehicle.templateName, vehicle.templateName)

    def onExitVehicle(self, player, vehicle):
        if 1 != self.__state:
            return 0
        self.sendEventMessage("exitVehicle", player.index, -1, "Unknown", vehicle.templateName)

    def onVehicleDestroyed(self, vehicle, attacker):
        if 1 != self.__state:
            return 0
        self.sendEventMessage("vehicleDestroyed", -1, vehicle.templateName)

    #
    # Chat Events
    #
    def onChatMessage(self, player_id, text, channel, flags):
        if 1 != self.__state:
            return 0
        if player_id == -1:
            self.sendEventMessage("chatServer", channel, flags, text)
        else:
            player = bf2.playerManager.getPlayerByIndex(player_id)
            self.sendEventMessage("chatPlayer", channel, flags, player.index, stripmessage(text))


class OutputBuffer(object):
    """A stateful output buffer.

    This knows how to enqueue data and ship it out without blocking.
    """

    def __init__(self, modManager, socket, allowBatching):
        self.mm = modManager
        self.allowBatching = allowBatching
        self.socket = socket
        self.data = []
        self.index = 0

    def enqueue(self, str):
        try:
            self.data.append(str)
        except Exception, e:
            self.mm.error("Failed to enqueue '%s' (%s)" % (str, e), True)

    def update(self):
        while len(self.data) > 0:
            try:
                item = self.data[0]
                scount = self.socket.send(item[self.index:])
                self.index += scount
                if self.index == len(item):
                    del self.data[0]
                    self.index = 0
            except socket.error, detail:
                if detail[0] != errno.EWOULDBLOCK:
                    self.mm.error("Failed to send", True)
                    return detail[1]
            if not self.allowBatching:
                break
        return None


# Helper methods
# TODO: Save id on the object
def findId(object):
    pos = object.getPosition()
    ids = getObjectsIdsOfTemplate(object.templateName)
    for id in ids:
        try:
            host.rcon_invoke("object.active id%s" % str(id))
            pos2 = host.rcon_invoke('object.absoluteposition')
            pos2 = map(float, pos2.split('/'))

            # Distance within 1m of the object we're checking
            if vectorDistance(pos, pos2) < 1:
                # host.rcon_invoke('echo "id: %s"' % str(id))
                return id

        except Exception, detail:
            host.rcon_invoke('echo "woops: %s"' % detail)
    return -1


def vectorDistance(u, v):
    d = [math.fabs(a - b) for a, b in zip(u, v)]
    return math.sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2])


def setPlayerPosition(player, pos):
    if player and player.isAlive():
        playerVehicle = player.getVehicle()
        rootVehicle = bf2.objectManager.getRootParent(playerVehicle)
        rootVehicle.setPosition((pos[0], pos[1], pos[2]))


def setPlayerRotation(player, rot):
    if player and player.isAlive():
        playerVehicle = player.getVehicle()
        rootVehicle = bf2.objectManager.getRootParent(playerVehicle)
        rootVehicle.setRotation((rot[0], rot[1], rot[2]))


def setVehiclePosition(vehicle, pos):
    if vehicle and pos:
        rootVehicle = bf2.objectManager.getRootParent(vehicle)
        rootVehicle.setPosition((pos[0], pos[1], pos[2]))


def setPlayerDamage(player, damage):
    if player and player.isAlive():
        try:
            soldier = player.getDefaultVehicle()
            rootVehicle = bf2.objectManager.getRootParent(player.getVehicle())
            rootVehicle.setDamage(damage)
            if damage < 10:
                soldier.setDamage(damage)
                sid = findId(rootVehicle)
                host.rcon_invoke('object.active id%s' % str(sid))
                host.rcon_invoke('object.delete')
                vid = findId(rootVehicle)
                host.rcon_invoke('object.active id%s' % str(vid))
                host.rcon_invoke('object.delete')
        except Exception, detail:
            pass


def awardPlayer(player, medalnum, medalval):
    #medals = { 'gold': 2051907, 'silver': 2051919, 'bronze': 2051902, 'ph': 2191608, 'bm': 2190703 }
    if player:
        bf2.gameLogic.sendMedalEvent(p, medalnum, medalval)


def setPlayerRank(player, ranknum, rankevent):
    # rankevent True then it pops up on the player's screen
    if player:
        # Ranks 0-21 only
        if ranknum >= 0 and ranknum <= 21:
            if rankevent:
                bf2.gameLogic.sendRankEvent(player, ranknum, 0)
                player.score.rank = ranknum
            else:
                player.score.rank = ranknum


def getPositionString(obj):
    pos = bf2.objectManager.getRootParent(obj).getPosition()
    return "%.1f/%.1f/%.1f" % (round(pos[0], 1), round(pos[1], 1), round(pos[2], 1))


def getRotationString(obj):
    rot = bf2.objectManager.getRootParent(obj).getRotation()
    return "%.1f/%.1f/%.1f" % (round(rot[0], 1), round(rot[1], 1), round(rot[2], 1))


def getVectorDistance(pos1, pos2):
    diffVec = [0.0, 0.0, 0.0]
    diffVec[0] = math.fabs(pos1[0] - pos2[0])
    diffVec[1] = math.fabs(pos1[1] - pos2[1])
    diffVec[2] = math.fabs(pos1[2] - pos2[2])

    # Application of Pythagorean theorem to calculate total distance
    return math.sqrt(diffVec[0] * diffVec[0] + diffVec[1] * diffVec[1] + diffVec[2] * diffVec[2])


def getMapList():
    maplist = host.rcon_invoke("maplist.list")
    pattern = re.compile(r'^\d+:\s\"(.*?)\"\sgpm_cq\s(\d{2})$', re.MULTILINE)
    result = []
    for maplist in pattern.findall(maplist):
        result.append(maplist[0].lower() + "|" + maplist[1])
    return result


def stripmessage(text):
    text = text.replace("HUD_TEXT_CHAT_TEAM", "")
    text = text.replace("HUD_TEXT_CHAT_SQUAD", "")
    text = text.replace("HUD_TEXT_CHAT_COMMANDER", "")
    text = text.replace("HUD_CHAT_DEADPREFIX", "")
    #text = text.replace("�1DEAD�0", "DEAD")
    text = text.replace("*�1DEAD�0*", "")
    text = text.replace("*DEAD*", "")
    text = text.replace("�1DEAD�0", "")
    return text


def get_int(string):
    try:
        num = int(string.strip('"\' '))
    except ValueError:
        num = None
    return num


def getObjectsIdsOfTemplate(templateName):
    arr = []
    try:
        objs = host.rcon_invoke(('object.listObjectsOfTemplate ' + str(templateName)))
        objs = objs.split()
        for i in range((len(objs) / 10)):
            objectId = ((i * 10) + 3)
            arr.append(objs[objectId])
    except:
        pass
    return arr


#
# ModManager load
#
def mm_load(modManager):
    """Creates and returns your object."""
    return WebAdmin(modManager)
