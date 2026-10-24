-- account/firebase_thread.lua
-- Runs outside the LÖVE main loop. Supports LÖVE's native https module or LuaSec.

local json = require "json"
local req = love.thread.getChannel("blockcraft_auth_requests")
local res = love.thread.getChannel("blockcraft_auth_responses")
local config = require "account.firebase_config"

local function quote(s)
  s = tostring(s or "")
  return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
end

local function encode(v)
  if type(v) == "table" then
    local parts = {}
    local array = (#v > 0)
    if array then
      for i = 1, #v do parts[#parts + 1] = encode(v[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    for k, value in pairs(v) do parts[#parts + 1] = quote(k) .. ":" .. encode(value) end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif type(v) == "string" then return quote(v)
  elseif type(v) == "number" or type(v) == "boolean" then return tostring(v)
  end
  return "null"
end

local function request(method, url, payload)
  local body = payload and encode(payload) or nil
  local headers = { ["Content-Type"] = "application/json" }
  if body then headers["Content-Length"] = tostring(#body) end

  local nativeOK, native = pcall(require, "https")
  if nativeOK and native and type(native.request) == "function" then
    local a, b, c = native.request(url, {method = method, headers = headers, data = body})
    if type(a) == "number" then return tostring(b or ""), a end
    return tostring(a or ""), tonumber(b) or 0
  end

  local sslOK, ssl = pcall(require, "ssl.https")
  local ltnOK, ltn = pcall(require, "ltn12")
  if sslOK and ltnOK then
    local chunks = {}
    local ok, code = ssl.request{
      url = url, method = method, headers = headers,
      source = body and ltn.source.string(body) or nil,
      sink = ltn.sink.table(chunks), protocol = "tlsv1_2",
    }
    return table.concat(chunks), tonumber(code) or (ok and 200 or 0)
  end
  return "", 0, "Online login unavailable: this mobile LÖVE build has no HTTPS module. Add lua-https to the LÖVE 11.4+ app, or run with LÖVE 12."
end

local function decoded(body)
  if not body or body == "" then return {} end
  local ok, value = pcall(json.decode, body)
  return ok and value or {}
end

local function fail(code, body, transportError)
  local data = decoded(body)
  local message = data.error and (data.error.message or data.error) or transportError or ("Firebase request failed (HTTP " .. tostring(code) .. ").")
  return false, tostring(message)
end

local function run(op, data)
  if not config.apiKey or config.apiKey == "" or config.apiKey:find("PASTE_", 1, true) then
    return false, "Firebase Web API key is not configured in account/firebase_config.lua."
  end
  local base = (config.databaseURL or ""):gsub("/$", "")
  local key = config.apiKey
  if op == "login" then
    local email = data.email
    if not email or email == "" then
      local body, code, transport = request("GET", base .. "/usernames/" .. data.username .. ".json", nil)
      if code < 200 or code >= 300 then return fail(code, body, transport) end
      local found = decoded(body)
      email = type(found) == "table" and found.email or found
    end
    if type(email) ~= "string" or email == "" then return false, "Username was not found. Use the email address for this account." end
    local body, code, transport = request("POST", "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=" .. key,
      {email = email, password = data.password, returnSecureToken = true})
    if code < 200 or code >= 300 then return fail(code, body, transport) end
    local auth = decoded(body)
    return true, {uid = auth.localId, idToken = auth.idToken, refreshToken = auth.refreshToken, email = email, username = data.username}
  elseif op == "register" then
    local body, code, transport = request("POST", "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=" .. key,
      {email = data.email, password = data.password, returnSecureToken = true})
    if code < 200 or code >= 300 then return fail(code, body, transport) end
    local auth = decoded(body)
    local profile = {uid = auth.localId, username = data.username, email = data.email}
    local pbody, pcode, ptransport = request("PUT", base .. "/users/" .. auth.localId .. ".json?auth=" .. tostring(auth.idToken), profile)
    if pcode < 200 or pcode >= 300 then return fail(pcode, pbody, ptransport) end
    local ubody, ucode, utransport = request("PUT", base .. "/usernames/" .. data.username .. ".json?auth=" .. tostring(auth.idToken), {uid = auth.localId, email = data.email})
    if ucode < 200 or ucode >= 300 then return fail(ucode, ubody, utransport) end
    return true, {uid = auth.localId, idToken = auth.idToken, refreshToken = auth.refreshToken, email = data.email, username = data.username}
  elseif op == "reset" then
    local body, code, transport = request("POST", "https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=" .. key,
      {requestType = "PASSWORD_RESET", email = data.email})
    if code < 200 or code >= 300 then return fail(code, body, transport) end
    return true, {email = data.email}
  end
  return false, "Unknown Firebase auth operation."
end

while true do
  local raw = req:demand()
  local ok, requestData = pcall(json.decode, raw)
  if ok and type(requestData) == "table" then
    local callOK, authOK, result = pcall(run, requestData.op, requestData.data or {})
    if callOK then
      res:push(encode({id = requestData.id, ok = authOK, result = result}))
    else
      res:push(encode({id = requestData.id, ok = false, result = tostring(authOK)}))
    end
  else
    res:push(encode({id = 0, ok = false, result = "Invalid authentication request."}))
  end
end
