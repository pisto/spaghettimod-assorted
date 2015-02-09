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

local function nmapline(ci, line)
  local proxyscan = ci.extra.proxyscan
  for port, service in line:gmatch(" (%d+)/open/tcp//([^/]*)") do
    port = tonumber(port)
    if not proxyscan.foundports[port] then
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
  pingdata.seenseq = seq
end
spaghetti.addhook(server.N_CLIENTPING, L"if _.ci.extra.proxyscan then _.ci.extra.proxyscan.ping.reported = _.ping end", true)

spaghetti.addhook("connected", function(info)
  local ip = ipstring(info.ci)
  local proxyscan
  proxyscan = {
    foundports = {}, ping = { tot = 0, mean = 0, m2 = 0, seenseq = 0 },
    pipes = { ping = newpipe("ping -On " .. ip, pingline) },
    nmapdelayed = spaghetti.later(15000, function()
      proxyscan.pipes.nmap = newpipe(("nmap -n -oG - -Pn -p %s %s"):format(table.concat(proxyports, ","), ip), nmapline)
      proxyscan.nmapdelayed = nil
    end)
  }
  info.ci.extra.proxyscan = proxyscan
  playermsg("The server will now run a \f3proxy check\f7 on your host. \f2Disconnect within 15 seconds if you do not agree to be scanned for open ports\f7. For more information type \f0#proxyscan", info.ci)
end)
local function closepipes(ci)
  for _, p in pairs(ci.extra.proxyscan.pipes) do killpipe(p) end
  ci.extra.proxyscan.pipes = {}
end
spaghetti.addhook("clientdisconnect", function(info)
  closepipes(info.ci)
  return info.ci.extra.proxyscan.nmapdelayed and spaghetti.cancel(info.ci.extra.proxyscan.nmapdelayed)
end)
spaghetti.addhook("shuttingdown", function() for ci in iterators.clients() do closepipes(ci) end end)

spaghetti.later(1000, function() for ci in iterators.clients() do
  local proxyscan = ci.extra.proxyscan
  for f, p in pairs(proxyscan.pipes) do
    repeat
      local data = p.pipe and fs.readsome(p.pipe)
      if not data then killpipe(p) proxyscan.pipes[f] = nil break end
      p.buff = p.buff .. data
    until data == ""
    p.buff = p.buff:gsub("[^\n]*\n", function(line) p.handler(ci, line) return "" end)
  end
  if next(proxyscan.foundports) and not proxyscan.exendednmap then
    proxyscan.exendednmap, proxyscan.pipes.nmap2 = true, newpipe("nmap -n -oG - -Pn " .. ipstring(ci), nmapline)
  end
end end, true)

local round = L"math.modf(_1 * 10) / 10"
require"std.commands".add("proxyscan", function(info)
  local ci = info.ci
  if info.args == "" then
    playermsg("The proxy scan checks for common proxy/server open ports on your host, and will ping it with ICMP packets for the duration of your stay. The port scan can be interrupted by leaving the server. When a port is found no action is taken but the port is logged. No attempt is made to determine the nature of the service running on the port. The results can be accessed with #proxyscan <cn> by yourself and authenticated masters. The code of this scan is available at \f0pisto.horse/proxyscan", ci)
    return
  end
  local tci = tonumber(info.args)
  if not tci then playermsg("Please specify a valid client number.", ci) return end
  tci = engine.getclientinfo(tci)
  if not tci then playermsg("Cannot find client.", ci) return end
  if ci.privilege < server.PRIV_AUTH and ci.clientnum ~= tci.ownernum then playermsg("You lack access to run this command.", ci) return end
  local tci, peer = engine.getclientinfo(tci.ownernum), engine.getclientpeer(tci.ownernum)
  local ping = tci.extra.proxyscan.ping
  local loss, icmpmean, icmpstd = 1 - ping.tot / ping.seenseq, pingstats(tci)
  playermsg(("proxyscan %s:\n\tping: reported %s enetping %d +- %d icmping %s +- %s loss %s"):format(server.colorname(ci, nil), ping.reported or "N/A", peer.roundTripTime, peer.roundTripTimeVariance, icmpmean and round(icmpmean) or "N/A", icmpstd and round(icmpstd) or "N/A", loss == loss and round(100 * loss) .. '%' or "N/A"), ci)
  local pipes, ports = ci.extra.proxyscan.pipes, map.lp(L"_1 .. '(' .. _2 .. ')'", ci.extra.proxyscan.foundports)
  if ci.extra.proxyscan.nmapdelayed or pipes.nmap or pipes.nmap2 then table.insert(ports, 1, "<pending>") end
  return #ports > 0 and playermsg("\tports: " .. table.concat(ports, ", "), ci)
end, "Usage: #proxyscan [cn]: show proxyscan results for client, or no arguments for more information on the scan")
