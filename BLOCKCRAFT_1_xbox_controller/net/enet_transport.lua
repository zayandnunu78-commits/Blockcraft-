-- The real network connection (uses the enet library that comes with LÖVE).
local enet = require "enet"

local T = {}
T.__index = T

function T.new()
  return setmetatable({host = enet.host_create(), server = nil}, T)
end

function T:connect(address)
  self.server = self.host:connect(address, 2)
end

function T:send(text, reliable)
  if not self.server then return end
  if reliable then self.server:send(text, 0, "reliable")
  else self.server:send(text, 1, "unreliable") end
end

function T:poll()
  local events = {}
  local ok, ev = pcall(self.host.service, self.host, 0)
  while ok and ev do
    if ev.type == "connect" then events[#events + 1] = {type = "connect"}
    elseif ev.type == "receive" then events[#events + 1] = {type = "receive", data = ev.data}
    elseif ev.type == "disconnect" then events[#events + 1] = {type = "disconnect"} end
    ok, ev = pcall(self.host.service, self.host, 0)
  end
  return events
end

function T:disconnect()
  if self.server then
    pcall(self.server.disconnect, self.server)
    pcall(self.host.flush, self.host)
    self.server = nil
  end
end

return T
