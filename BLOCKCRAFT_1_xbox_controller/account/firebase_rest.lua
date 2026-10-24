-- account/firebase_rest.lua
-- Main-thread bridge for account/firebase_thread.lua.
-- Requests are JSON messages on LÖVE thread channels; callbacks run in love.update.

local json = require "json"
local M = {}
M.__index = M

local function quote(s)
  s = tostring(s or "")
  return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
end

local function encode(v)
  if type(v) == "table" then
    local parts, array = {}, (#v > 0)
    if array then for i = 1, #v do parts[#parts + 1] = encode(v[i]) end
    else for k, value in pairs(v) do parts[#parts + 1] = quote(k) .. ":" .. encode(value) end end
    return (array and "[" or "{") .. table.concat(parts, ",") .. (array and "]" or "}")
  elseif type(v) == "string" then return quote(v)
  elseif type(v) == "number" or type(v) == "boolean" then return tostring(v) end
  return "null"
end

function M.new(opts)
  opts = opts or {}
  local self = setmetatable({
    requests = love.thread.getChannel("blockcraft_auth_requests"),
    responses = love.thread.getChannel("blockcraft_auth_responses"),
    callbacks = {}, nextID = 0, thread = nil, threadPath = opts.threadPath or "account/firebase_thread.lua",
  }, M)
  -- auth_interface.lua invokes backend methods as backend.login(payload, callback),
  -- not backend:login(payload, callback). Bind wrappers so both conventions are safe.
  self.login = function(payload, callback) return M.login(self, payload, callback) end
  self.register = function(payload, callback) return M.register(self, payload, callback) end
  self.resetPassword = function(payload, callback) return M.resetPassword(self, payload, callback) end
  return self
end

function M:start()
  if self.thread then return end
  self.thread = love.thread.newThread(self.threadPath)
  self.thread:start()
end

function M:send(op, data, callback)
  self:start()
  self.nextID = self.nextID + 1
  self.callbacks[self.nextID] = callback
  self.requests:push(encode({id = self.nextID, op = op, data = data or {}}))
end

function M:login(payload, callback)
  local email = payload.username:find("@", 1, true) and payload.username or nil
  self:send("login", {username = payload.username, email = email, password = payload.password}, callback)
end

function M:register(payload, callback)
  self:send("register", payload, callback)
end

function M:resetPassword(payload, callback)
  self:send("reset", payload, callback)
end

function M:update()
  while true do
    local raw = self.responses:pop()
    if not raw then break end
    local ok, response = pcall(json.decode, raw)
    if ok and type(response) == "table" then
      local callback = self.callbacks[response.id]
      self.callbacks[response.id] = nil
      if callback then callback(response.ok == true, response.result) end
    end
  end
end

function M:stop()
  if self.thread and self.thread:isRunning() then self.thread:release() end
  self.thread = nil
end

return M
