--[[

  Scan connecting clients for proxy ports (VPN software or generic server software), monitor icmp ping.
  For those concerned: this is just like what irc networks do when you join. Live with it.

]]--

local fp, L, fs, ip, iterators, playermsg = require"utils.fp", require"utils.lambda", require"utils.fs", require"utils.ip", require"std.iterators", require"std.playermsg"
local map = fp.map
local posix = require"posix"

--                   web,           ssh, assorted vpn software, email
local proxyports = { 80, 8080, 443, 22, 943, 1723, 1194, 1701, 143, 993, 110, 995, 465, 587 }

local function ipstring(ci)
  return tostring(ip.ip(engine.ENET_NET_TO_HOST_32(engine.getclientip(ci.clientnum))))
end

local function newpipe(cmd, handler)
  local p, pid = fs.popenpid(cmd)
  return p and { pipe = p, buff = "", handler = handler, pid = pid }
end
local function killpipe(pipe)
  posix.kill(pipe.pid)
  pipe.pipe:close()
end

local nmapline
nmapline = function(ci, line)
  local proxyscan = ci.extra.proxyscan
  for port, service in line:gmatch(" (%d+)/open/tcp//([^/]*)") do
    port = tonumber(port)
    if not proxyscan.foundports[port] then
      if not next(proxyscan.foundports) then proxyscan.pipes.nmap2 = newpipe("nmap -n -oG - -Pn " .. ipstring(ci), nmapline) end
      proxyscan.foundports[port] = service
      engine.writelog(("nmap: %s (%d) %s port %d (%s)"):format(ci.name, ci.clientnum, ipstring(ci), port, service))
    end
  end
end

local function pingstats(ci)
  local pingdata = ci.extra.proxyscan.ping
  if pingdata.tot < 2 then return end
  return pingdata.mean, math.sqrt(pingdata.m2 / (pingdata.tot - 1))
end
local function pingline(ci, line)
  local seq, ping = map.uv(tonumber, line:match("^64 bytes from [%d%.]+: icmp_seq=(%d+) ttl=%d+ time=(%d+%.?%d+) ms\n"))
  if not seq then return end
  local pingdata = ci.extra.proxyscan.ping
  pingdata.tot = pingdata.tot + 1
  local delta = ping - pingdata.mean
  pingdata.mean = pingdata.mean + delta / pingdata.tot
  pingdata.m2 = pingdata.m2 + delta * (ping - pingdata.mean)
  if seq < pingdata.seenseq then pingdata.lost = pingdata.lost - 1 return end
  pingdata.lost, pingdata.seenseq = seq - pingdata.seenseq - 1, seq
end
spaghetti.addhook(server.N_CLIENTPING, L"if _.ci.extra.proxyscan then _.ci.extra.proxyscan.ping.reported = _.ping end", true)

spaghetti.addhook("connected", function(info)
  local ip = ipstring(info.ci)
  info.ci.extra.proxyscan = { pipes = {
    nmap = newpipe(("nmap -n -oG - -Pn -p %s %s"):format(table.concat(proxyports, ","), ip), nmapline),
    ping = newpipe("ping -On " .. ip, pingline),
  }, foundports = {}, ping = { tot = 0, mean = 0, m2 = 0, seenseq = 0, lost = 0 }}
end)
local function closepipes(ci)
  ci = ci.ci or ci
  for _, p in pairs(ci.extra.proxyscan.pipes) do killpipe(p) end
  ci.extra.proxyscan.pipes = {}
end
spaghetti.addhook("clientdisconnect", closepipes)
spaghetti.addhook("shuttingdown", function() for ci in iterators.clients() do closepipes(ci) end end)

spaghetti.later(1000, function() for ci in iterators.clients() do
  local proxyscan = ci.extra.proxyscan
  for f, p in pairs(proxyscan.pipes) do
    repeat
      local data = p.pipe and fs.readsome(p.pipe)
      if not data then killpipe(p) proxyscan.pipes[f] = nil goto nextpipe end
      p.buff = p.buff .. data
    until data == ""
    p.buff = p.buff:gsub("[^\n]*\n", function(line) p.handler(ci, line) return "" end)
    :: nextpipe ::
  end
end end, true)

local round = L"math.modf(_1 * 10) / 10"
require"std.commands".add("proxyscan", function(info)
  local ci = info.ci
  if ci.privilege < server.PRIV_AUTH then playermsg("You lack access to this command.", ci) return end
  local tci = tonumber(info.args)
  if not tci then playermsg("Please specify a valid client number.", ci) return end
  tci = engine.getclientinfo(tci)
  if not tci then playermsg("Cannot find client.", ci) return end
  local tci, peer = engine.getclientinfo(tci.ownernum), engine.getclientpeer(ci.ownernum)
  local ping = tci.extra.proxyscan.ping
  local loss, icmpmean, icmpstd = ping.lost / ping.seenseq, pingstats(tci)
  playermsg(("proxiscan %s:\n\tping: reported %s enetping %d +- %d icmping %s +- %s loss %s"):format(server.colorname(ci, nil), ping.reported or "N/A", peer.roundTripTime, peer.roundTripTimeVariance, icmpmean and round(icmpmean) or "N/A", icmpstd and round(icmpstd) or "N/A", loss == loss and round(100 * loss) .. '%' or "N/A"), ci)
  local ports = ci.extra.proxyscan.foundports
  if not next(ports) then return end
  playermsg("\tports: " .. table.concat(map.lp(L"_1 .. '(' .. _2 .. ')'", ports), ", "), ci)
end, "Usage: #proxyscan <cn>: show proxyscan results")
