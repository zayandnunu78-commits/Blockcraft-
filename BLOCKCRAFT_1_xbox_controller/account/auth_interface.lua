-- account/auth_interface.lua
-- Backend-neutral authentication adapter for Blockcraft 1 and Blockcraft 2.
--
-- The UI never talks to Firebase or FastAPI directly. Supply a backend object
-- with asynchronous methods that accept (payload, callback):
--   backend.login(payload, callback)
--   backend.register(payload, callback)
--   backend.resetPassword(payload, callback)
--
-- Callback contract:
--   callback(true, result) on success
--   callback(false, "readable error") on failure
--
-- A real FastAPI/Firebase client can be connected later without changing the UI.

local M = {}
M.__index = M

local function finish(callback, ok, value)
  if callback then callback(ok, value) end
end

local function clean(value)
  if type(value) ~= "string" then return "" end
  return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function validateCredentials(username, password)
  username = clean(username)
  if #username < 3 then return nil, "Username must be at least 3 characters." end
  if #password < 6 then return nil, "Password must be at least 6 characters." end
  return {username = username, password = password}
end

function M.new(backend)
  return setmetatable({backend = backend}, M)
end

function M:setBackend(backend)
  self.backend = backend
end

function M:isConnected()
  return self.backend ~= nil
end

function M:login(username, password, callback)
  local payload, err = validateCredentials(username, password)
  if not payload then finish(callback, false, err); return end
  if not self.backend or type(self.backend.login) ~= "function" then
    finish(callback, false, "Online login is not connected yet. Choose Play Offline or connect the FastAPI backend.")
    return
  end
  self.backend.login(payload, callback)
end

function M:register(username, email, password, confirm, callback)
  username, email = clean(username), clean(email)
  if #username < 3 then finish(callback, false, "Username must be at least 3 characters."); return end
  if not email:match("^[^%s@]+@[^%s@]+%.[^%s@]+$") then
    finish(callback, false, "Enter a valid email address."); return
  end
  if #password < 6 then finish(callback, false, "Password must be at least 6 characters."); return end
  if password ~= confirm then finish(callback, false, "Passwords do not match."); return end
  if not self.backend or type(self.backend.register) ~= "function" then
    finish(callback, false, "Account registration is not connected yet. Connect the FastAPI backend first.")
    return
  end
  self.backend.register({username = username, email = email, password = password}, callback)
end

function M:resetPassword(email, callback)
  email = clean(email)
  if not email:match("^[^%s@]+@[^%s@]+%.[^%s@]+$") then
    finish(callback, false, "Enter the email address used for your account.")
    return
  end
  if not self.backend or type(self.backend.resetPassword) ~= "function" then
    finish(callback, false, "Password recovery is not connected yet. Connect the FastAPI backend first.")
    return
  end
  self.backend.resetPassword({email = email}, callback)
end

return M
