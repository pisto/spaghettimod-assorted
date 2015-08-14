--[[

  SSLLITE configuration: quick script for the SSL guys, because I just had not enough time to test all the things
  with anticheat and authentication.
  
  #startmatch: setup SSL match
  #endmatch: tear down SSL match
  #checkmatch: check that every player is connected directly to the hidden servers
  #spawn: spawn a player (e.g. after a forced team switch)
  #tie [no|#seconds]: set tie breaker mode

]]--

local SSLport = os.getenv("SSLLITE")
if not SSLport then return end
SSLport = assert(tonumber(SSLport), "Invalid port SSLLITE=" .. SSLport)
engine.writelog("Applying the SSLLITE configuration on port " .. SSLport)

local servertag = require"utils.servertag"
servertag.tag = "SSLLITE-" .. SSLport

local fp, L = require"utils.fp", require"utils.lambda"
local map = fp.map
local abuse, playermsg, iterators, putf = require"std.abuse", require"std.playermsg", require"std.iterators", require"std.putf"

cs.maxclients = 128
cs.serverport = SSLport
cs.updatemaster = 0
cs.mastername = ""
cs.publicserver = 1
cs.serverauth = "SSL-admin"
local auth = require"std.auth"
table.insert(auth.preauths, "SSL-admin")
cs.serverdesc = "\f7SSL " .. SSLport
cs.ctftkpenalty = 0
cs.lockmaprotation = 2
cs.restrictpausegame = 0
require("std.flushinterval").set(5)

cs.maprotationreset()
--copied from data/menus.cfg
local ffamaps, capturemaps, ctfmaps = table.concat({
  "aard3c academy akaritori alithia alloy aqueducts arbana bvdm_01 castle_trap collusion complex corruption curvedm curvy_castle darkdeath deathtek depot",
  "dirtndust DM_BS1 dock douze duel7 duel8 dune elegy fanatic_quake force fragplaza frostbyte frozen fury guacamole gubo hades",
"hashi hog2 industry injustice island justice kalking1 katrez_d kffa killfactory kmap5 konkuri-to ksauer1 legazzo lostinspace masdm mbt10",
  "mbt2 mbt9 memento metl2 metl3 metl4 moonlite neondevastation neonpanic nmp8 nucleus oasis oddworld ogrosupply orbe orion osiris",
  "ot outpost paradigm park pgdm phosgene pitch_black powerplant refuge renegade rm5 roughinery ruby ruine sauerstruck sdm1 shadowed",
  "shindou shinmei1 shiva simplicity skrdm1 stemple suburb tartech teahupoo tejen thetowers thor torment tumwalk turbine wake5 wdcd"
}, " "), table.concat({
  "abbey akroseum alithia arabic asgard asteroids c_egypt c_valley campo capture_night caribbean collusion core_refuge core_transfer corruption cwcastle damnation",
  "dirtndust donya duomo dust2 eternal_valley evilness face-capture fb_capture fc3 fc4 fc5 forge frostbyte hades hallo haste hidden",
  "infamy killcore3 kopenhagen lostinspace mbt12 mercury monastery nevil_c nitro nmp4 nmp8 nmp9 nucleus ogrosupply paradigm ph-capture reissen",
  "relic river_c serenity snapper_rocks spcr subterra suburb tempest tortuga turbulence twinforts urban_c valhalla venice xenon"
}, " "), table.concat({
  "abbey akroseum arbana asgard authentic autumn bad_moon berlin_wall bt_falls campo capture_night catch22 core_refuge core_transfer damnation desecration dust2",
  "eternal_valley europium evilness face-capture flagstone forge forgotten garden hallo haste hidden infamy kopenhagen l_ctf mach2 mbt1 mbt12",
  "mbt4 mercury mill nitro nucleus recovery redemption reissen sacrifice shipwreck siberia snapper_rocks spcr subterra suburb tejen tempest",
  "tortuga turbulence twinforts urban_c valhalla wdcd xenon"
}, " ")

ffamaps, capturemaps, ctfmaps = map.uv(function(maps)
  local t = map.f(L"_", maps:gmatch("[^ ]+"))
  for i = 2, #t do
    local j = math.random(i)
    local s = t[j]
    t[j] = t[i]
    t[i] = s
  end
  return table.concat(t, " ")
end, ffamaps, capturemaps, ctfmaps)

cs.maprotation("ffa effic tac teamplay efficteam tacteam", ffamaps, "regencapture capture hold effichold instahold", capturemaps, "ctf efficctf instactf protect efficprotect instaprotect collect efficcollect instacollect", ctfmaps)

cs.adduser("pisto", "SSL-admin", "+f198cd6e656129b898b7bb8d794211bd768aae54717d57df", "a")
cs.adduser("Frosty", "SSL-admin", "-d1d22314f8dd21a1e038833cdd74feaf020b8aa7af534725", "a")
cs.adduser("swatllama", "SSL-admin", "+d4e443aedd4dc3053f9a8de4769890d24361ebfea9a89046", "a")
cs.adduser("Fear", "SSL-admin", "+f5d80f128fe66475bad292ea87d361f28e84093038d4184f", "a")


local function SSLadmins_z()
  return iterators.minpriv(server.PRIV_ADMIN)
end
local function SSLadmins()
  return map.sf(L"_", SSLadmins_z())
end

local commands = require"std.commands"
require"std.pm"
require"std.enetping"

abuse.ratelimit({ server.N_TEXT, server.N_SAYTEAM }, 0.5, 10, L"nil, 'I don\\'t like spam.'")
abuse.ratelimit(server.N_SWITCHNAME, 1/30, 4, L"nil, 'You\\'re a pain.'")
abuse.ratelimit(server.N_SERVCMD, 0.5, 10, L"nil, 'Yes I\\'m filtering this too.'")

--ratelimit just gobbles the packet. Use the selector to add a tag to the exceeding message, and append another hook to send the message
local function warnspam(packet)
  if not packet.ratelimited or type(packet.ratelimited) ~= "string" then return end
  playermsg(packet.ratelimited, packet.ci)
end
map.nv(function(type) spaghetti.addhook(type, warnspam) end,
  server.N_TEXT, server.N_SAYTEAM, server.N_SWITCHNAME, server.N_SERVCMD
)

local git = io.popen("echo `git rev-parse --short HEAD` `git show -s --format=%ci`")
local gitversion = git:read()
git = nil, git:close()
commands.add("info", function(info)
  playermsg("spaghettimod is a reboot of hopmod for programmers. Is being used for SSL.\nKindly brought to you by pisto." .. (gitversion and "\nCommit " .. gitversion or ""), info.ci)
end)


--Broadcast IPs to admins

local ip = require"utils.ip"
require"std.getip"


--match

local maploaded, clanwar, tie, delayresume, chatisolate, specall, autospawn = require"std.maploaded", require"std.clanwar", require"gamemods.tie", require"std.delayresume", require"std.chatisolate", require"std.specall", require"gamemods.autospawn"

local match, manualtie, manualautospawn

spaghetti.addhook(server.N_MAPVOTE, function(info)
  if info.skip or info.ci.privilege >= server.PRIV_ADMIN or not match then return end
  info.skip = true
end)

spaghetti.addhook("changemap", function()
  if not match then return end
  chatisolate(true)
end)

spaghetti.addhook("intermission", function()
  if not match then return end
  chatisolate(false)
end)

local directip = require"std.directip"
if not next(directip.directIP) then engine.writelog("Cannot know the public ip, #checkmatch will be useless") end

local function resetmatch()
  if not match then return end
  match = nil
  clanwar(false)
  tie(false)
  autospawn(false)
  manualtie, manualautospawn = nil
  delayresume.delay = 0
  chatisolate(false)
end

commands.add("startmatch", function(info)
  if info.ci.privilege < server.PRIV_ADMIN then return playermsg("Only SSL admins can do this.", info.ci) end
  clanwar(true)
  tie(false)
  autospawn(false)
  manualtie, manualautospawn = nil
  delayresume.delay = 5
  if server.interm == 0 then chatisolate(true) end
  server.pausegame(true, nil)
  match = true
  playermsg(server.colorname(info.ci, nil) .. "\f3 activated the match mode, tie breaker/autospawn now off.", SSLadmins_z())
end, "#startmatch: setup SSL mode")

spaghetti.addhook("noclients", function()
  return match and server.forcepaused(true)
end)

commands.add("endmatch", function(info)
  if info.ci.privilege < server.PRIV_ADMIN then return playermsg("Only SSL admins can do this.", info.ci) end
  if not match then return end
  resetmatch()
  playermsg(server.colorname(info.ci, nil) .. "\f3 has reset the match mode, tie breaker/autospawn now off.", SSLadmins_z())
end, "#endmatch: finish SSL mode")


--#checkmatch

local function checkmatch()
  local nodirect = {}
  for ci in iterators.players() do nodirect[ci] = not directip.directclient(ci) or nil end
  return not next(nodirect) and not server.m_edit, nodirect
end

local function checkmatch_broadcast()
  if not match then return end
  if checkmatch() then playermsg("\f0SSL match ready.", SSLadmins_z()) end
end
spaghetti.addhook("connected", function(info)
  return (info.ci.extra.sslident or info.ci.state.state ~= engine.CS_SPECTATOR) and checkmatch_broadcast()
end)
spaghetti.addhook("specstate", checkmatch_broadcast)

commands.add("checkmatch", function(info)
  if info.ci.privilege < server.PRIV_ADMIN then playermsg("Insufficient privileges.", info.ci) return end
  if not match then playermsg("No match set.", info.ci) return end
  local ok, nodirect = checkmatch()
  if ok then playermsg("\f0SSL match ready.", info.ci) return end
  local msg = "\f3SSL match not ready.\f7"
  if next(nodirect) then msg = msg .. "\nNon direct connection: " .. table.concat(map.lp(L"server.colorname(_, nil)", nodirect), ", ") end
  if server.m_edit then msg = msg .. "\nMode is coopedit!" end
  playermsg(msg, SSLadmins_z())
end, "#checkmatch: check if every SSL user is in place")

local resuming = false
spaghetti.addhook("pausegame", function() resuming = false end)
spaghetti.addhook(server.N_PAUSEGAME, function(info)
  if info.ci.privilege < server.PRIV_ADMIN then return end
  local printwarning = not resuming and not checkmatch()
  resuming = not resuming and server.gamepaused
  return printwarning and playermsg("\f3Warning, it doesn't seem that the match is ready. \f7Verify with #checkmatch", SSLadmins_z())
end)


--#spawn

commands.add("spawn", function(info)
  if info.ci.privilege < server.PRIV_ADMIN then playermsg("Insufficient privileges.", info.ci) return end
  local t = engine.getclientinfo(tonumber(info.args) or -1)
  if not t then playermsg("Invalid cn " .. info.args, info.ci) return end
  if t.state.state ~= engine.CS_SPECTATOR then server.sendspawn(t)
  else playermsg("Cannot spawn a spectator.", info.ci) end
end, "#spawn <cn>: force a client spawn")


--#tie

commands.add("tie", function(info)
  if info.ci.privilege < server.PRIV_ADMIN then playermsg("Insufficient privileges.", info.ci) return end
  local tieseconds = tonumber(info.args)
  if tieseconds and tieseconds >= 0 then
    manualtie = tieseconds
    tie(tieseconds * 1000, false, tieseconds > 0 and ("\f6TIE!!\f0 Time left is \f2%d seconds\f0!"):format(manualtie) or "\f6TIE!!\f0 \f2First\f0 score wins!")
  elseif info.args:lower():match("^ *no *$") then
    manualtie = nil
    tie(false)
  elseif info.args:match("%S") then playermsg("Unknown tie mode " .. info.args, info.ci) return end
  local msg = "Tie mode: "
  if not manualtie then msg = msg .. "not set"
  elseif manualtie == 0 then msg = msg .. "first score"
  else msg = msg .. manualtie .. " seconds" end
  playermsg(msg, info.ci)
end, "#tie [no|#seconds]: show/set tie mode (seconds = 0 for golden goal).")


--#autospawn
commands.add("autospawn", function(info)
  if info.ci.privilege < server.PRIV_ADMIN then playermsg("Insufficient privileges.", info.ci) return end
  local autospawnseconds = tonumber(info.args)
  if autospawnseconds and autospawnseconds >= 0 then
    manualautospawn = autospawnseconds
    autospawn(manualautospawn  * 1000)
  elseif info.args:lower():match("^ *no *$") then
    manualautospawn = false
    autospawn(false)
  elseif info.args:match("%S") then playermsg("Unknown autospawn mode " .. info.args, info.ci) return end
  local msg = "Autospawn mode: "
  if not manualautospawn then msg = msg .. "off"
  elseif manualautospawn == 0 then msg = msg .. "immediate"
  else msg = msg .. manualautospawn .. " seconds" end
  playermsg(msg, info.ci)
end, "#autospawn [no|#seconds]: show/set autospawn mode.")


--resume

require"std.settime"
require"std.setteamscore"
require"std.setscore"
