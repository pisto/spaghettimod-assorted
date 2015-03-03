--[[

  A server which only runs Honzik flagrun mode.

]]--

if not os.getenv("HONZIKVPS") then return end
engine.writelog("Applying the Honzik configuration.")

local servertag = require"utils.servertag"
servertag.tag = "honzik"

local uuid = require"std.uuid"

local fp, L = require"utils.fp", require"utils.lambda"
local map, range, fold, last, pick, I = fp.map, fp.range, fp.fold, fp.last, fp.pick, fp.I
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
table.insert(auth.preauths, "honzik")

local nameprotect = require"std.nameprotect"
local protectdb = nameprotect.on(true)
protectdb["^pisto$"] = { pisto = { pisto = true } }

cs.serverdesc = "GHOST FLAGRUN"

cs.lockmaprotation = 2
cs.maprotationreset()

local honzikmaps = map.f(I, ("abbey akroseum arbana asgard authentic autumn bad_moon berlin_wall bt_falls campo capture_night catch22 core_refuge core_transfer damnation desecration dust2 eternal_valley europium evilness face-capture flagstone forge forgotten garden hallo haste hidden infamy kopenhagen l_ctf mach2 mbt1 mbt12 mbt4 mercury mill nitro nucleus recovery redemption reissen sacrifice shipwreck siberia snapper_rocks spcr subterra suburb tejen tempest tortuga turbulence twinforts urban_c valhalla wdcd xenon frostbyte fc4 gubo killcore3 konkuri-to ogrosupply donya caribbean duomo fc5 alloy depot"):gmatch("[^ ]+"))
for i = 2, #honzikmaps do
  local j = math.random(i)
  local s = honzikmaps[j]
  honzikmaps[j] = honzikmaps[i]
  honzikmaps[i] = s
end

cs.maprotation("instactf efficctf", table.concat(honzikmaps, " "))
server.mastermask = server.MM_PUBSERV + server.MM_AUTOAPPROVE
spaghetti.addhook(server.N_MAPVOTE, function(info)
  if info.skip or info.ci.privilege > 0 or info.text ~= server.smapname then return end
  info.skip = true
  playermsg("Cannot revote the current map.", info.ci)
end)

require"std.pm"

--gamemods

local ctf, putf, sound, iterators, n_client = server.ctfmode, require"std.putf", require"std.sound", require"std.iterators", require"std.n_client"
require"std.notalive"

spaghetti.addhook(server.N_ADDBOT, L"_.skip = true")
local calcscoreboard, attachflagghost, removeflagghost, disappear

--never dead
local function respawn(ci)
  ci.state:respawn()
  server.sendspawn(ci)
end
spaghetti.addhook("specstate", function(info) return info.ci.state.state ~= engine.CS_SPECTATOR and respawn(info.ci) end)
spaghetti.addhook("damaged", function(info) return info.target.state.state == engine.CS_DEAD and respawn(info.target) end)
spaghetti.addhook(server.N_SUICIDE, function(info)
  info.skip = true
  if info.ci.state.state == engine.CS_SPECTATOR then return end
  respawn(info.ci)
end)


--flag logic. Assume only two flags.

spaghetti.addhook("changemap", function()
  server.gamelimit = 5 * 60 * 1000;
  engine.sendpacket(-1, 1, putf({10, r = 1}, server.N_TIMEUP, server.gamelimit / 1000):finalize(), -1)
end)

--switch spawnpoints, keep only the nearest
local ents, vec3 = require"std.ents", require"utils.vec3"
spaghetti.addhook("entsloaded", function()
  local teamflags = map.mf(function(i, _, ment)
    if ment.attr2 ~= 1 and ment.attr2 ~= 2 then return end
    return ment.attr2, { o = vec3(ment.o), nearestdist = 1/0 }
  end, ents.enum(server.FLAG))
  for i, _, ment in ents.enum(server.PLAYERSTART) do
    local flag = teamflags[ment.attr2]
    if flag then
      local dist = flag.o:dist(ment.o)
      if dist > 30 and dist < flag.nearestdist then
        if flag.nearesti then ents.delent(flag.nearesti) end
        flag.nearestdist, flag.nearesti = dist, i
      else ents.delent(i) end
    end
  end
  for team, ent in pairs(teamflags) do
    local i, _, ment = ents.getent(ent.nearesti)
    ents.editent(i, server.PLAYERSTART, ment.o, ment.attr1, 3 - ment.attr2)
  end
end)
spaghetti.addhook("connected", L"_.ci.state.state ~= engine.CS_SPECTATOR and server.sendspawn(_.ci)") --fixup for spawn on connect

local function resetflag(ci)
  if not ci.extra.flag then return end
  engine.sendpacket(ci.clientnum, 1, putf({r = 1}, server.N_RESETFLAG, ci.extra.flag, ci.state.lifesequence, -1, 0, 0):finalize(), -1)
  ci.extra.flag, ci.extra.runstart = nil
  removeflagghost(ci)
end


spaghetti.addhook(server.N_TRYDROPFLAG, function(info)
  if info.skip then return end
  info.skip = true
  if info.ci.state.state == engine.CS_SPECTATOR then return end
  resetflag(info.ci)
end)
spaghetti.addhook("spawned", function(info)
  resetflag(info.ci)
  engine.sendpacket(info.ci.clientnum, 1, putf({10, r=1}, server.N_INITFLAGS, 0, 0, 2, info.ci.state.lifesequence, -1, -1, 0, 0, info.ci.state.lifesequence, -1, -1, 0, 0):finalize(), -1)
end)
spaghetti.addhook("specstate", function(info) return info.ci.state.state == engine.CS_SPECTATOR and resetflag(info.ci) end)
local best
spaghetti.addhook("changemap", function(info) for ci in iterators.all() do ci.extra.flag, ci.extra.bestrun, ci.extra.runstart, best = nil end end)
spaghetti.addhook("clientdisconnect", function(info)
  if not best or best.clientnum ~= info.ci.clientnum then return end
  best = nil
  for ci in iterators.all() do
    if ci.clientnum ~= info.ci.clientnum and (ci.extra.bestrun or 1/0) < (best and best.extra.bestrun or 1/0) then best = ci end
  end
end)

local function flagnotice(ci, s, o)
  for oci in iterators.all() do if ci.clientnum ~= oci.clientnum then
    engine.sendpacket(oci.clientnum, 1, n_client(putf({2, r = 1}, server.N_SOUND, s, server.N_SOUND, s), oci):finalize(), -1)
  end end
  o = vec3(o)
  o.z = o.z + 8
  local i = ents.active() and ents.newent(server.PARTICLES, o, 3, 12, ci.extra.flagghostcolor)
  if not i then return end
  spaghetti.latergame(300, function() ents.delent(i) end)
end

spaghetti.addhook(server.N_TAKEFLAG, function(info)
  if info.skip then return end
  info.skip = true
  local ci = info.ci
  local state, extra = ci.state, ci.extra
  local lfs, cn = state.lifesequence, ci.clientnum
  if state.state == engine.CS_SPECTATOR or info.version ~= lfs then return end
  local ownedflag, takeflag = extra.flag, info.flag
  if takeflag < 0 or takeflag > 1 or ownedflag == takeflag then return end
  if not ownedflag then
    extra.flag, extra.runstart = takeflag, server.gamemillis
    engine.sendpacket(cn, 1, putf({10, r = 1}, server.N_TAKEFLAG, cn, takeflag, lfs):finalize(), -1)
    attachflagghost(ci)
    flagnotice(ci, server.S_FLAGPICKUP, ctf.flags[takeflag].spawnloc)
  else
    engine.sendpacket(cn, 1, putf({10, r = 1}, server.N_SCOREFLAG, cn, ownedflag, lfs, takeflag, lfs, -1, server.ctfteamflag(ci.team), 0, state.flags):finalize(), -1)
    local elapsed = server.gamemillis - extra.runstart
    extra.flag, extra.runstart = nil
    removeflagghost(ci)
    flagnotice(ci, server.S_FLAGSCORE, ctf.flags[takeflag].spawnloc)
    local oldrun = extra.bestrun
    local msg = "Flagrun time: \f2" .. elapsed / 1000 .. "\f7 seconds"
    if oldrun and oldrun ~= elapsed then
      local delta = elapsed - oldrun
      msg = msg .. " (" .. (delta < 0 and "\f0" or "\f3+") .. delta / 1000 .. "\f7)"
    end
    playermsg(msg, ci)
    if not best or best.extra.bestrun > elapsed then
      local diff = best and elapsed - best.extra.bestrun
      server.sendservmsg("\f7" .. server.colorname(ci, nil) .. " \f6takes the lead\f7! \f2" .. elapsed / 1000 .. "\f7 seconds" .. (diff and " (\f0" .. diff / 1000 .. "\f7)" or ""))
      best = ci
    end
    if oldrun and oldrun <= elapsed then return end
    extra.bestrun = elapsed
    calcscoreboard()
  end
end)


--[[
  hack the scoreboard to show flagrun time. client sees all in his own team.
  Use flags to enforce order and show best run millis as frags
]]--

spaghetti.addhook("autoteam", function(info)
  info.skip = true
  if info.ci then info.ci.team = "good" end
end)

local function changeteam(ci, team, refresh)
  team = engine.filtertext(team, false):sub(1, server.MAXTEAMLEN)
  if team ~= "good" and team ~= "evil" or (ci.team == team and not refresh) then return end
  ci.team = team
  local p = putf({10, r = 1})
  for ci in iterators.all() do putf(p, server.N_SETTEAM, ci.clientnum, team, -1) end
  engine.sendpacket(ci.clientnum, 1, p:finalize(), -1)
  if refresh or ci.state.state == engine.CS_SPECTATOR then return end
  resetflag(ci)
  respawn(ci)
end

spaghetti.addhook(server.N_SETTEAM, function(info)
  if info.skip then return end
  info.skip = true
  if not info.wi or info.wi.clientnum ~= info.ci.clientnum and info.ci.privilege == server.PRIV_NONE then return end
  changeteam(info.ci, info.text)
end)

spaghetti.addhook(server.N_SWITCHTEAM, function(info)
  local skip = info.skip
  if info.skip then return end
  info.skip = true
  changeteam(info.ci, info.text)
end)

spaghetti.addhook(server.N_PING, L"_.skip = true")
spaghetti.addhook(server.N_CLIENTPING, L"_.skip = true")

calcscoreboard = function()
  for revindex, ci in ipairs(table.sort(map.lf(L"_", iterators.all()), L"(_1.extra.bestrun or 1/0) > (_2.extra.bestrun or 1/0)")) do
    revindex = ci.extra.bestrun and revindex or 0
    ci.state.flags = revindex
    server.sendresume(ci)
    engine.sendpacket(-1, 1, n_client(putf({10, r = 1}, server.N_CLIENTPING, ci.extra.bestrun or -1), ci):finalize(), -1)
  end
  disappear()
end

spaghetti.addhook("savegamestate", L"_.sc.extra.bestrun = _.ci.extra.bestrun")
spaghetti.addhook("restoregamestate", L"_.ci.extra.bestrun = _.sc.extra.bestrun")
spaghetti.addhook("connected", function()
  for ci in iterators.all() do changeteam(ci, ci.team, true) end
  calcscoreboard()
end)
spaghetti.addhook("changemap", calcscoreboard)

local position = { "\f01st \f2", "\f02nd \f2", "\f03rd \f2" }
spaghetti.addhook("intermission", function()
  local classify = table.sort(map.lf(L"_", pick.fz(L"_.extra.bestrun", iterators.all())), L"_1.extra.bestrun < _2.extra.bestrun")
  if #classify == 0 then return end
  local msg = "\f2Best flagrunners\f7:"
  for i = 1, 3 do
    if not classify[i] then break end
    local ci = classify[i]
    msg = msg .. "\n\t" .. position[i] .. server.colorname(ci, nil) .. "\f7: " .. ci.extra.bestrun / 1000 .. " seconds"
  end
  server.sendservmsg(msg)
end)


-- ghost mode: force players to be in CS_SPAWN state, attach an entity without collision box to their position

--prevent accidental (?) damage
spaghetti.addhook("dodamage", function(info) info.skip = info.target.clientnum ~= info.actor.clientnum end)
spaghetti.addhook("damageeffects", function(info)
  if info.target.clientnum == info.actor.clientnum then return end
  local push = info.hitpush
  push.x, push.y, push.z = 0, 0, 0
end)

local spectators, blindcns, emptypos = {}, {}, {buf = ('\0'):rep(13)}

disappear = function()
  local players = map.sf(L"_.state.state == engine.CS_ALIVE and _ or nil", iterators.players())
  for viewer in pairs(players) do for vanish in pairs(players) do if vanish.clientnum ~= viewer.clientnum then
    local p = putf({ 30, r = 1}, server.N_SPAWN)
    server.sendstate(vanish.state, p)
    engine.sendpacket(viewer.clientnum, 1, n_client(p, vanish):finalize(), -1)
  end end end
end

spaghetti.later(900, disappear, true)

spaghetti.addhook("connected", function(info)
  if info.ci.state.state == engine.CS_SPECTATOR then spectators[info.ci.clientnum] = true return end
end)

spaghetti.addhook("specstate", function(info)
  if info.ci.state.state == engine.CS_SPECTATOR then spectators[info.ci.clientnum] = true return end
  spectators[info.ci.clientnum] = nil
  --clear the virtual position of players so sounds do not get played at random locations
  local p
  for ci in iterators.players() do if ci.clientnum ~= info.ci.clientnum then
    p = putf(p or {13, r = 1}, server.N_POS, {uint = ci.clientnum}, { ci.state.lifesequence % 2 * 8 }, emptypos)
  end end
  if not p then return end
  engine.sendpacket(info.ci.clientnum, 0, p:finalize(), -1)
end)

spaghetti.addhook("clientdisconnect", function(info) spectators[info.ci.clientnum], blindcns[info.ci.clientnum] = nil end)

spaghetti.addhook("worldstate_pos", function(info)
  info.skip = true
  local position = info.ci.position.buf
  local p = engine.enet_packet_create(position, 0)
  for scn in pairs(spectators) do engine.sendpacket(scn, 0, p, -1) end
  server.recordpacket(0, position)
end)

local trackent = require"std.trackent"

local ghostmodels = {
  "aftas/arvores/arp",
  "carrot",
  "crow",
  "dcp/bulb",
  "dcp/firebowl",
  "dcp/grass",
  "dcp/groundlamp",
  "dcp/hanginlamp",
  "dcp/insect",
  "dcp/ivy",
  "dcp/jumppad2",
  "dcp/leafs",
  "dcp/mushroom",
  "dcp/plant1",
  "dcp/reed",
  "dcp/smplant",
  "dcp/switch2a",
  "makke/fork",
  "makke/spoon",
  "mapmodels/justice/exit-sign",
  "mapmodels/justice/railings/02",
  "mapmodels/nieb/plant01",
  "mapmodels/nieb/plant02",
  "mapmodels/nieb/sandcastle",
  "mapmodels/nieb/sign_no-exit",
  "mapmodels/sitters/gothic/skelet1",
  "mapmodels/sitters/gothic/skelet2",
  "mapmodels/sitters/gothic/skelet3",
  "mapmodels/yves_allaire/e6/e6fanblade/horizontal",
  "mapmodels/yves_allaire/e6/e6fanblade/vertical",
  "objects/axe",
  "objects/bed01",
  "objects/fire",
  "objects/lamp01",
  "objects/lamp02",
  "objects/lantern02",
  "objects/med_chand",
  "objects/millblade",
  "objects/sign01",
  "objects/torch",
  "objects/torch_cold",
  "objects/well_base",
  "objects/well_roof",
  "switch1",
  "switch2",
  "vegetation/bush01",
  "vegetation/tree07",
  "vegetation/weeds"
}
map.sti(ghostmodels, L"_2", ghostmodels)

local function attachghost(ci)
  ci.extra.ghost = ents.active() and trackent.add(ci, function(i, lastpos)
    local o = vec3(lastpos.pos)
    o.z = o.z + 5
    local eid = ents.mapmodels[ci.extra.ghostmodel]
    if eid then ents.editent(i, server.MAPMODEL, o, lastpos.yaw, eid)
    else ents.editent(i, server.CARROT, o, 0) end
  end, false, not ci.extra.showself, blindcns)
end
spaghetti.addhook("connected", function(info)
  info.ci.extra.ghostmodel = ghostmodels[math.random(#ghostmodels)]
  attachghost(info.ci)
  info.ci.extra.flagghostcolor = math.random(0, 0xFFF)
end)
spaghetti.addhook("changemap", function() for ci in iterators.all() do
  ci.extra.ghost, ci.extra.flagghost = nil
  attachghost(ci)
end end)

attachflagghost = function(ci)
  ci.extra.flagghost = ents.active() and trackent.add(ci, function(i, lastpos)
    local o = vec3(lastpos.pos)
    o.z = o.z + 15
    ents.editent(i, server.PARTICLES, o, 0, 200, 80, ci.extra.flagghostcolor)
  end, false, not ci.extra.showself, blindcns) or nil
end
removeflagghost = function(ci)
  if not ci.extra.flagghost then return end
  trackent.remove(ci, ci.extra.flagghost)
  ci.extra.flagghost = nil
end

commands.add("ghosts", function(info)
  local extra = info.ci.extra
  if info.args == "none" then blindcns[info.ci.clientnum], extra.showself = true
  elseif info.args == "all" then extra.showself, blindcns[info.ci.clientnum] = true
  elseif info.args == "others" then blindcns[info.ci.clientnum], extra.showself = nil
  else playermsg("Missing argument <all|others|none>\n#ghosts <all|others|none> : select which ghosts to show, all -> everybody including yourself, others -> only other players, none -> nobody", info.ci) end
  for ci in iterators.all() do
    trackent.remove(ci, ci.extra.ghost)
    attachghost(ci)
    if ci.extra.flagghost then
      trackent.remove(ci, ci.extra.flagghost)
      attachflagghost(ci)
    end
  end
end, "#ghosts <all|others|none> : select which ghosts to show, all -> everybody including yourself, others -> only other players, none -> nobody")

commands.add("setghost", function(info)
  local cn, model, color = info.args:match("(%d*) *([^ ]*) *([%xx]*) *")
  if cn == "" and model == "" and color == "" then
    if not ents.mapmodels then playermsg("No map models list for this map.", info.ci) return end
    playermsg("Available models (\f0green\f7 -> no collision box):", info.ci)
    local function print(i, mname) playermsg("\t" .. i .. (ghostmodels[mname] and "\f0\t" or "\t") .. mname, info.ci) end
    if ents.mapmodels[0] then print(0, ents.mapmodels[0]) end
    for i, mname in ipairs(ents.mapmodels) do print(i, mname) end
    return
  end
  if (color ~= "" or model ~= "") and info.ci.privilege < server.PRIV_AUTH then playermsg("You lack privileges to change players' ghosts", info.ci) return end
  local tci = cn == "" and info.ci or server.getinfo(tonumber(cn) or -1)
  if not tci then playermsg("Invalid cn " .. cn, info.ci) return end
  if color ~= "" and not tonumber(color) then playermsg("Invalid color " .. color, info.ci) return end
  if model ~= "" and tonumber(model) then
    local model_ = ents.mapmodels and ents.mapmodels[tonumber(model)]
    if not model_ then playermsg("Model index out of range", info.ci) return end
    model = model_
  end
  tci.extra.ghostmodel, tci.extra.flagghostcolor = model ~= "" and model or tci.extra.ghostmodel, color ~= "" and tonumber(color) or tci.extra.flagghostcolor
  local mname = tci.extra.ghostmodel
  if ghostmodels[mname] then mname = "\f0" .. mname end
  playermsg("Ghost for " .. server.colorname(tci, nil) .. ": " .. mname .. " \f7flag " .. ("0x%03X"):format(tci.extra.flagghostcolor), info.ci)
end, "#setghost [cn] [model [0xcolor]] :\n\tno arguments -> show list of available models for this map\n\tcn -> show model for cn\n\tcn model -> set model for cn\n\tcn model color -> set model and flag flame color for cn")

commands.add("showself", function(info) playermsg("Command #showself is now deprecated, use #ghosts", info.ci) end)


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
abuse.ratelimit(server.N_TRYDROPFLAG, 1/10, 10, L"nil, 'Baaaaahh'")
abuse.ratelimit(server.N_TAKEFLAG, 1/3, 10, L"nil, 'Beeeehh'")

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
  server.N_TEXT, server.N_SAYTEAM, server.N_SWITCHNAME, server.N_MAPVOTE, server.N_SPECTATOR, server.N_MASTERMODE, server.N_AUTHTRY, server.N_AUTHKICK, server.N_CLIENTPING, server.N_TRYDROPFLAG, server.N_TAKEFLAG
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

--simple banner

banner = "\n\n\f2FLAGRUN SERVER\f7. Fastest \f3base\f7-to-\f1base\f7 run with flag wins. Best run is in the ping column.\nOther players see you as some \f6random prop\f7, and you won't collide with them.\nUse \f0#ghosts all\f7 and \f0/thirdperson 1\f7 to see your beautiful metamorphosis."
spaghetti.addhook("maploaded", function(info)
  info.ci.extra.bannershown = true
  local ciuuid = info.ci.extra.uuid
  spaghetti.later(1000, function()
    local ci = uuid.find(ciuuid)
    return ci and playermsg(banner, ci)
  end)
end)

local git = io.popen("echo `git rev-parse --short HEAD` `git show -s --format=%ci`")
local gitversion = git:read()
git = nil, git:close()
commands.add("info", function(info)
  playermsg("spaghettimod is a reboot of hopmod for programmers. Will be used for SDoS.\nKindly brought to you by pisto." .. (gitversion and "\nCommit " .. gitversion or ""), info.ci)
end)
