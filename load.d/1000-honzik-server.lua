--[[

  A server which only runs Honzik flagrun mode.

]]--

if not os.getenv("HONZIKVPS") then return end
engine.writelog("Applying the Honzik configuration.")

local servertag = require"utils.servertag"
servertag.tag = "honzik"

local uuid = require"std.uuid"

local fp, L = require"utils.fp", require"utils.lambda"
local map, range, fold, last, I = fp.map, fp.range, fp.fold, fp.last, fp.I
local abuse, playermsg, commands = require"std.abuse", require"std.playermsg", require"std.commands"

cs.maxclients = 42
cs.serverport = 23456

--make sure you delete the next two lines, or I'll have admin on your server.
cs.serverauth = "pisto"
local auth = require("std.auth")
cs.adduser("pisto", "pisto", "+8ce1687301aea5c4500df0042849191f875c70555c3cc4c9", "a")
cs.adduser("Honzik", "honzik", "-01463cd5dd576d90c7f39854816c98b8336834951f6762e2", "a")
cs.adduser("Cedii**", "ASkidban-bypass", "-4e75e0e92e6512415a8114e1db856af36d00e801615a3e98", "n")
cs.adduser("xcb567", "ASkidban-bypass", "+41b02bfb90f87d403a864e722d2131a5c7941f2b35491d0f", "n")
cs.adduser("M0UL", "ASkidban-bypass", "+640728e15ab552342b68a293f2c6b3e15b5adf1be53fd4f2", "n")
table.insert(auth.preauths, "pisto")

local nameprotect = require"std.nameprotect"
local protectdb = nameprotect.on(true)
protectdb["^pisto$"] = { pisto = { pisto = true } }

cs.serverdesc = "Honzik tests"

cs.lockmaprotation = 2
cs.maprotationreset()

local honzikmaps = map.f(I, ("abbey akroseum arbana asgard authentic autumn bad_moon berlin_wall bt_falls campo capture_night catch22 core_refuge core_transfer damnation desecration dust2 eternal_valley europium evilness face-capture flagstone forge forgotten garden hallo haste hidden infamy kopenhagen l_ctf mach2 mbt1 mbt12 mbt4 mercury mill nitro nucleus recovery redemption reissen sacrifice shipwreck siberia snapper_rocks spcr subterra suburb tejen tempest tortuga turbulence twinforts urban_c valhalla wdcd xenon"):gmatch("[^ ]+"))
for i = 2, #honzikmaps do
  local j = math.random(i)
  local s = honzikmaps[j]
  honzikmaps[j] = honzikmaps[i]
  honzikmaps[i] = s
end

cs.maprotation("collect instacollect efficcollect", table.concat(honzikmaps, " "))
cs.publicserver = 2
spaghetti.addhook(server.N_MAPVOTE, function(info)
  if info.skip or info.ci.privilege > 0 or info.text ~= server.smapname then return end
  info.skip = true
  playermsg("Cannot revote the current map.", info.ci)
end)

require"std.pm"

--gamemods

local collect, putf, sound, iterators, n_client = server.collectmode, require"std.putf", require"std.sound", require"std.iterators", require"std.n_client"
require"std.notalive"

local suppress = L"_.skip = true"
spaghetti.addhook("servmodedied", L"_.skip = true")
spaghetti.addhook(server.N_ADDBOT, L"_.skip = true")

local function removebasetokens(ci)
  local p
  for b = 0, collect.bases:length() - 1 do
    p = p or putf({10, r = 1}, server.N_EXPIRETOKENS)
    putf(p, b)
  end
  return p and engine.sendpacket(ci.clientnum, 1, putf(p, -1):finalize(), -1)
end
local function spawnbasetokens(ci)
  removebasetokens(ci)
  local teamid, p = server.collectteambase(ci.team)
  for b = 0, collect.bases:length() - 1 do
    b = collect.bases[b]
    if b.team == teamid then
      p = p or putf({10, r = 1}, server.N_INITTOKENS, 0, 0, collect.bases:length())
      putf(p, b.id, b.team, math.random(1, 360), b.o.x * server.DMF, b.o.y * server.DMF, b.o.z * server.DMF)
    end
  end
  return p and engine.sendpacket(ci.clientnum, 1, putf(p, -1):finalize(), -1)
end
local function setnumtokens(ci, tot)
  engine.sendpacket(-1, 1, putf({10, r = 1}, server.N_TAKETOKEN, ci.clientnum, -1, tot):finalize(), -1)
  ci.state.tokens = tot
end

spaghetti.addhook("notalive", function(info)
  info.ci.extra.basetoken = nil
  setnumtokens(info.ci, 0)
  spawnbasetokens(info.ci)
  if info.ci.state.state ~= engine.CS_SPECTATOR then
    info.ci.state:respawn()
    server.sendspawn(info.ci)
  end
end)
spaghetti.addhook("connected", function(info)
  spawnbasetokens(info.ci)
  for ci in iterators.players() do if ci.clientnum ~= info.ci.clientnum then
    local p = putf({ 30, r = 1}, server.N_SPAWN)
    server.sendstate(ci.state, p)
    engine.sendpacket(info.ci.clientnum, 1, n_client(p, ci):finalize(), -1)
  end end
end)
spaghetti.addhook("changemap", function(info)
  for ci in iterators.players() do  
    ci.extra.basetoken = nil
    spawnbasetokens(ci)
  end
end)

spaghetti.addhook(server.N_TAKETOKEN, function(info)
  info.skip = true
  if collect.notgotbases or info.ci.state.state ~= engine.CS_ALIVE or info.ci.extra.basetoken or not collect.bases:inrange(info.id) then return end
  info.ci.extra.basetoken, info.ci.state.tokens = info.id, 1
  engine.sendpacket(info.ci.clientnum, 1, putf({10, r = 1}, server.N_TAKETOKEN, info.ci.clientnum, info.id, 1):finalize(), -1)
  removebasetokens(info.ci)
  sound(info.ci, server.S_FLAGPICKUP)
end)

spaghetti.addhook(server.N_DEPOSITTOKENS, function(info)
  info.skip = true
  if collect.notgotbases or info.ci.state.state ~= engine.CS_ALIVE or not info.ci.extra.basetoken or info.ci.extra.basetoken == info.id then return end
  info.ci.extra.basetoken = nil
  spawnbasetokens(info.ci)
  sound(info.ci, server.S_FLAGSCORE)
end)

spaghetti.addhook("worldstate_pos", L"_.skip = true")
local trackent, ents = require"std.trackent", require"std.ents"
local function attachghost(ci)
  return ents.active() and trackent.add(ci, function(i, lastpos)
    ents.editent(i, server.MAPMODEL, lastpos.pos, lastpos.yaw, "carrot")
  end, false, true)
end
spaghetti.addhook("connected", function(info) attachghost(info.ci) end)
spaghetti.addhook("changemap", function() for ci in iterators.clients() do attachghost(ci) end end)

--moderation

--limit reconnects when banned, or to avoid spawn wait time
abuse.reconnectspam(1/60, 5)

--limit some message types
spaghetti.addhook(server.N_KICK, function(info)
  if info.skip or info.ci.privilege > server.PRIV_MASTER then return end
  info.skip = true
  playermsg("No. Use gauth.", info.ci)
end)
spaghetti.addhook(server.N_SOUND, function(info)
  if info.skip or abuse.clientsound(info.sound) then return end
  info.skip = true
  playermsg("I know I used to do that but... whatever.", info.ci)
end)
abuse.ratelimit({ server.N_TEXT, server.N_SAYTEAM }, 0.5, 10, L"nil, 'I don\\'t like spam.'")
abuse.ratelimit(server.N_SWITCHNAME, 1/30, 4, L"nil, 'You\\'re a pain.'")
abuse.ratelimit(server.N_MAPVOTE, 1/10, 3, L"nil, 'That map sucks anyway.'")
abuse.ratelimit(server.N_SPECTATOR, 1/30, 5, L"_.ci.clientnum ~= _.spectator, 'Can\\'t even describe you.'") --self spec
abuse.ratelimit(server.N_MASTERMODE, 1/30, 5, L"_.ci.privilege == server.PRIV_NONE, 'Can\\'t even describe you.'")
abuse.ratelimit({ server.N_AUTHTRY, server.N_AUTHKICK }, 1/60, 4, L"nil, 'Are you really trying to bruteforce a 192 bits number? Kudos to you!'")
abuse.ratelimit(server.N_CLIENTPING, 4.5) --no message as it could be cause of network jitter
abuse.ratelimit(server.N_SERVCMD, 0.5, 10, L"nil, 'Yes I\\'m filtering this too.'")

--prevent masters from annoying players
local tb = require"utils.tokenbucket"
local function bullying(who, victim)
  local t = who.extra.bullying or {}
  local rate = t[victim.extra.uuid] or tb(1/30, 6)
  t[victim.extra.uuid] = rate
  who.extra.bullying = t
  return not rate()
end
spaghetti.addhook(server.N_SETTEAM, function(info)
  if info.skip or info.who == info.sender or not info.wi or info.ci.privilege == server.PRIV_NONE then return end
  local team = engine.filtertext(info.text):sub(1, engine.MAXTEAMLEN)
  if #team == 0 or team == info.wi.team then return end
  if bullying(info.ci, info.wi) then
    info.skip = true
    playermsg("...", info.ci)
  end
end)
spaghetti.addhook(server.N_SPECTATOR, function(info)
  if info.skip or info.spectator == info.sender or not info.spinfo or info.ci.privilege == server.PRIV_NONE or info.val == (info.spinfo.state.state == engine.CS_SPECTATOR and 1 or 0) then return end
  if bullying(info.ci, info.spinfo) then
    info.skip = true
    playermsg("...", info.ci)
  end
end)

--ratelimit just gobbles the packet. Use the selector to add a tag to the exceeding message, and append another hook to send the message
local function warnspam(packet)
  if not packet.ratelimited or type(packet.ratelimited) ~= "string" then return end
  playermsg(packet.ratelimited, packet.ci)
end
map.nv(function(type) spaghetti.addhook(type, warnspam) end,
  server.N_TEXT, server.N_SAYTEAM, server.N_SWITCHNAME, server.N_MAPVOTE, server.N_SPECTATOR, server.N_MASTERMODE, server.N_AUTHTRY, server.N_AUTHKICK, server.N_CLIENTPING
)

--#cheater command
local home = os.getenv("HOME") or "."
local function ircnotify(args)
  --I use ii for the bots
  local cheaterchan, pisto = io.open(home .. "/irc/cheaterchan/in", "w"), io.open(home .. "/irc/ii/pipes/pisto/in", "w")
  for ip, requests in pairs(args) do
    local str = "#cheater" .. (requests.ai and " \x02through bots\x02" or "") .. " on pisto.horse 23456"
    if requests.total > 1 then str = str .. " (" .. requests.total .. " reports)" end
    str = str .. ": "
    local names
    for cheater in pairs(requests.cheaters) do str, names = str .. (names and ", \x02" or "\x02") .. engine.encodeutf8(cheater.name) .. " (" .. cheater.clientnum .. ")\x02", true end
    if not names then str = str .. "<disconnected>" end
    if cheaterchan then cheaterchan:write(str .. ", auth holders please help!\n") end
    if pisto then pisto:write(str .. " -- " .. tostring(require"utils.ip".ip(ip)) .. "\n") end
  end
  if cheaterchan then cheaterchan:close() end
  if pisto then pisto:close() end
end

abuse.cheatercmd(ircnotify, 20000, 1/30000, 3)
local sound = require"std.sound"
spaghetti.addhook(server.N_TEXT, function(info)
  if info.skip then return end
  local low = info.text:lower()
  if not low:match"cheat" and not low:match"hack" and not low:match"auth" and not low:match"kick" then return end
  local tellcheatcmd = info.ci.extra.tellcheatcmd or tb(1/30000, 1)
  info.ci.extra.tellcheatcmd = tellcheatcmd
  if not tellcheatcmd() then return end
  playermsg("\f2Problems with a cheater? Please use \f3#cheater [cn|name]\f2, and operators will look into the situation!\nYou can report bots too, the controlling client will be reported.", info.ci)
  sound(info.ci, server.S_HIT, true) sound(info.ci, server.S_HIT, true)
end)

require"std.enetping"

--simple banner

local git = io.popen("echo `git rev-parse --short HEAD` `git show -s --format=%ci`")
local gitversion = git:read()
git = nil, git:close()
commands.add("info", function(info)
  playermsg("spaghettimod is a reboot of hopmod for programmers. Will be used for SDoS.\nKindly brought to you by pisto." .. (gitversion and "\nCommit " .. gitversion or ""), info.ci)
end)
