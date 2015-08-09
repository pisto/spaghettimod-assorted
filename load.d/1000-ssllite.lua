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

local match, manualtie, autospawntime

spaghetti.addhook("changemap", function()
  if not match then return end
  chatisolate(true)
end)

spaghetti.addhook("intermission", function()
  if not match then return end
  chatisolate(false)
end)

local directip = require"std.directip"
do
  local localhost, foundpublic = ip.ip("127.0.0.1").ip
  for public in pairs(directip.directIP) do
    if public ~= localhost then foundpublic = public break end
  end
if not foundpublic then engine.writelog("Cannot know the public ip, #checkmatch will be useless") end
end

local function resetmatch()
  if not match then return end
  match = nil
  clanwar(false)
  tie(false)
  autospawn(false)
  manualtie, autospawntime = nil
  delayresume.delay = 0
  chatisolate(false)
end

commands.add("startmatch", function(info)
  if info.ci.privilege < server.PRIV_ADMIN then return playermsg("Only SSL admins can do this.", info.ci) end
  clanwar(true)
  tie(false)
  autospawn(false)
  manualtie, autospawntime = nil
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
  return not next(nodirect), nodirect
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
  if nodirect then msg = msg .. "\nNon direct connection: " .. table.concat(map.lp(L"server.colorname(_, nil)", nodirect), ", ") end
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
  local asseconds = tonumber(info.args)
  if asseconds and asseconds >= 0 then autospawntime = asseconds
  elseif info.args:lower():match("^ *no *$") then autospawntime = nil
  elseif info.args:match("%S") then playermsg("Unknown autospawn mode " .. info.args, info.ci) return end
  autospawn(autospawntime * 1000)
  local msg = "Autospawn mode: "
  if not autospawntime then msg = msg .. "not set"
  elseif autospawntime == 0 then msg = msg .. "immediate"
  else msg = msg .. autospawntime .. " seconds" end
  playermsg(msg, info.ci)
end, "#autospawn [no|#seconds]: show/set autospawn mode.")
