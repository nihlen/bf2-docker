# netsky-openbf2-inf

A placeholder, not an image: this folder has no `Dockerfile`, so the tests and CI skip it. The infantry server ran on
the retail image `netsky-inf` (stock maps, ModManager with `mm_autobalance`), which was removed with the other retail
netsky images. It has not been moved to OpenBF2.

To make it an image, copy the files of [openbf2-serverext](../openbf2-serverext) into this folder, add
`admin/netsky.py` from another `netsky-openbf2-*` image, and put the two files below in
`assets/build/bf2/mods/bf2/settings/`. Nothing else is needed: the old image had no custom maps and no map changes.

## maplist.con

```
maplist.append strike_at_karkand gpm_cq 16
maplist.append dragon_valley gpm_cq 16
maplist.append daqing_oilfields gpm_cq 16
maplist.append fushe_pass gpm_cq 16
maplist.append greatwall gpm_cq 16
maplist.append gulf_of_oman gpm_cq 16
maplist.append midnight_sun gpm_cq 16
maplist.append operation_clean_sweep gpm_cq 16
maplist.append operationharvest gpm_cq 16
maplist.append operationroadrage gpm_cq 16
maplist.append operationsmokescreen gpm_cq 16
maplist.append road_to_jalalabad gpm_cq 16
maplist.append sharqi_peninsula gpm_cq 16
maplist.append songhua_stalemate gpm_cq 16
maplist.append taraba_quarry gpm_cq 16
maplist.append zatar_wetlands gpm_cq 16
```

## serversettings.con

The old server's settings, as changes to
[openbf2-serverext's serversettings.con](../openbf2-serverext/assets/build/bf2/mods/bf2/settings/serversettings.con):

```
rem default ENV_SPONSOR_VARS=website=https://bf2.nihlen.net/;discord=https://discord.gg/DPaJaMKAc3;provider=bf2hub.com
sv.welcomeMessage "Maps: https://bf2.nihlen.net |Discord: https://discord.gg/DPaJaMKAc3"
sv.tkPunishEnabled 1
sv.tkNumPunishToKick 3
sv.teamVoteOnly 1
sv.adminScript "netsky"
sv.timeBeforeRestartMap 30
sv.voipQuality 3
sv.voipServerPort 55125
sv.useGlobalRank 1
sv.sponsorText "Infantry server located in Frankfurt, Germany.{{sponsor_vars}}"
sv.sponsorLogoURL "http://static.nihlen.net/bf2/61761115-server.jpg"
sv.communityLogoURL "http://static.nihlen.net/bf2/61761115-server.jpg"
sv.coopBotCount 16
```

The old image had an empty `sv.sponsorText`; the line above follows the other netsky images. `sv.tkPunishEnabled 1`
had no effect on the old server (ModManager's `mm_tk_punish` was not loaded) and has none with `admin/netsky.py`,
which does not start the stock `tk_punish` script either.
