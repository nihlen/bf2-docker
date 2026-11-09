# The admin script of the netsky-openbf2 servers (sv.adminScript "netsky" in serversettings.con). The server imports
# it from admin/ and calls init() once, update() every frame and shutdown() when it stops.
#
# It replaces Multiplay's ModManager v2.2c, of which only mm_autobalance (v2.5) was still used, with
#   allowCommander 0, allowSquadLeader 0, allowSquadMember 0, roundSwitch 1
# This is a port of that module with that configuration:
# - a connecting player who is not alive joins the team with fewer players (scaled by sv.teamRatioPercent)
# - when a round ends (EndGame -> PreGame), every player swaps teams
# - only with sv.autoBalanceTeam 1: a player who dies or changes teams is moved if the teams are uneven
# Kicks, bans and the console are BF2WebAdmin's admin channel (libserverext.so), not this script.
#
# The server embeds Python 2.3: no with, decorators, generator expressions, conditional expressions or set().
# print goes to host.log, which the server discards, so messages are written to the console (sys.__stdout__,
# /volume/bf2.log). Don't import standard_admin: its __init__ starts DICE's autobalance and tk_punish.

import sys
import traceback

import bf2
import host

enabled = False
lastStatus = bf2.GameStatus.PreGame
statusHandler = None


def log(text):
    sys.__stdout__.write('netsky: %s\n' % text)
    sys.__stdout__.flush()


def logged(handler):
    """The handler, writing its exceptions to the console (the server would not show them)."""
    def call(*args):
        try:
            handler(*args)
        except:
            log('%s failed: %s' % (handler.__name__, ''.join(traceback.format_exception(*sys.exc_info())).strip()))
    return call


def otherTeam(team):
    if team == 1:
        return 2
    return 1


def countTeams(players):
    """The number of players in team 1 and in team 2 (everyone not in team 1)."""
    team1 = 0
    team2 = 0
    for p in players:
        if p.getTeam() == 1:
            team1 += 1
        else:
            team2 += 1
    return team1, team2


def isBotGame():
    """A game with bots that is not co-op, where ModManager balances humans and bots differently."""
    return host.sgl_getIsAIGame() and host.ss_getParam('gameMode') != 'gpm_coop'


def onPlayerConnect(p):
    # Don't switch alive players, they would keep the other team's kit
    if not enabled or p.isAlive():
        return

    # The team with fewer players, not counting the new player
    team1, team2 = countTeams(bf2.playerManager.getPlayers())
    if p.getTeam() == 1:
        team1 -= 1
    else:
        team2 -= 1
    if team2 * bf2.serverSettings.getTeamRatioPercent() / 100.0 > team1:
        p.setTeam(1)
    else:
        p.setTeam(2)


def onPlayerDeath(p, vehicle):
    if not enabled or p is None:
        return
    if host.ss_getParam('gameMode') == 'gpm_coop' and p.isAIPlayer():
        return
    if not bf2.serverSettings.getAutoBalanceTeam():
        return

    # A suicide or team change (also the round switch below) is not balanced
    if p.getSuicide():
        p.setSuicide(0)
        return

    # allowCommander 0: never the commander
    if p.isCommander():
        return

    squad = p.getSquadId()
    team = p.getTeam()
    players = bf2.playerManager.getPlayers()

    # allowSquadLeader 0: a squad leader only if nobody else is in the squad
    if p.isSquadLeader():
        for tp in players:
            if tp.getSquadId() == squad and tp.index != p.index:
                return

    # allowSquadMember 0: a squad member only if the team has nobody outside a squad
    # (ModManager also tests p.isCommander() here, which is false after the check above)
    if squad > 0:
        for tp in players:
            if tp.getSquadId() == 0 and tp.getTeam() == team:
                return

    team1, team2 = countTeams(players)

    # In a bot game, humans are balanced only while there are more humans than bots
    if isBotGame() and not p.isAIPlayer():
        bots = 0
        for tp in players:
            if tp.isAIPlayer():
                bots += 1
        if bots >= len(players) - bots:
            return

    team2 = team2 * bf2.serverSettings.getTeamRatioPercent() / 100.0
    if team == 1 and team2 + 1 < team1:
        p.setTeam(2)
    elif team == 2 and team1 + 1 < team2:
        p.setTeam(1)


def onPlayerChangeTeams(p, humanHasSpawned):
    if not enabled or not bf2.serverSettings.getAutoBalanceTeam():
        return
    # Don't switch alive players, they would keep the other team's kit
    if p.isAlive():
        return

    players = bf2.playerManager.getPlayers()
    if isBotGame():
        # Before a human has spawned, a bot of the team the player joined moves to the other team
        if humanHasSpawned or p.isAIPlayer():
            return
        for tp in players:
            if tp.getTeam() == p.getTeam() and tp.isAIPlayer():
                tp.setTeam(otherTeam(p.getTeam()))
                return
    else:
        # The player can't make the teams uneven by more than one
        team1, team2 = countTeams(players)
        if abs(team1 - team2) > 1:
            p.setTeam(otherTeam(p.getTeam()))


def onGameStatusChanged(status):
    global lastStatus
    previous = lastStatus
    lastStatus = status
    # roundSwitch 1: at the end of a round every player swaps teams
    if status == bf2.GameStatus.PreGame and previous == bf2.GameStatus.EndGame:
        players = bf2.playerManager.getPlayers()
        for p in players:
            # Keeps onPlayerDeath from balancing the player back
            p.setSuicide(1)
            p.setTeam(otherTeam(p.getTeam()))
        log('round switch: %d players swapped teams' % len(players))


def init():
    global enabled, statusHandler
    host.registerHandler('PlayerConnect', logged(onPlayerConnect), 1)
    host.registerHandler('PlayerDeath', logged(onPlayerDeath), 1)
    host.registerHandler('PlayerChangeTeams', logged(onPlayerChangeTeams), 1)
    statusHandler = logged(onGameStatusChanged)
    host.registerGameStatusHandler(statusHandler)
    enabled = True
    log('admin script loaded: autobalance on connect, team switch at round end, sv.autoBalanceTeam %s'
        % bf2.serverSettings.getAutoBalanceTeam())


def shutdown():
    global enabled
    # The event handlers can't be unregistered, enabled turns them off
    enabled = False
    if statusHandler:
        host.unregisterGameStatusHandler(statusHandler)


def update():
    pass
