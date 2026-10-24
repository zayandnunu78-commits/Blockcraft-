-- Minimal JSON decoder (enough for fabric.mod.json, blockstates, models, lang files)
local J = {}

local escapes = {['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t'}

local function utf8char(cp)
  if cp < 0x80 then return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64)
  elseif cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
  end
  return string.char(0xF0 + math.floor(cp / 262144), 0x80 + math.floor(cp / 4096) % 64,
                     0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

function J.decode(s)
  if s:sub(1, 3) == "\239\187\191" then s = s:sub(4) end -- strip BOM
  local pos = 1

  local function fail(msg) error(("json: %s at char %d"):format(msg, pos), 0) end
  local function ws() pos = s:find("[^ \t\r\n]", pos) or #s + 1 end

  local value

  local function str()
    pos = pos + 1
    local out = {}
    while true do
      local c = s:sub(pos, pos)
      if c == "" then fail("unterminated string") end
      if c == '"' then pos = pos + 1; break end
      if c == "\\" then
        local e = s:sub(pos + 1, pos + 1)
        if e == "u" then
          local cp = tonumber(s:sub(pos + 2, pos + 5), 16) or fail("bad \\u escape")
          pos = pos + 6
          if cp >= 0xD800 and cp < 0xDC00 and s:sub(pos, pos + 1) == "\\u" then
            local lo = tonumber(s:sub(pos + 2, pos + 5), 16)
            if lo then cp = 0x10000 + (cp - 0xD800) * 1024 + (lo - 0xDC00); pos = pos + 6 end
          end
          out[#out + 1] = utf8char(cp)
        else
          out[#out + 1] = escapes[e] or fail("bad escape")
          pos = pos + 2
        end
      else
        local nxt = s:find('["\\]', pos) or #s + 1
        out[#out + 1] = s:sub(pos, nxt - 1)
        pos = nxt
      end
    end
    return table.concat(out)
  end

  function value()
    ws()
    local c = s:sub(pos, pos)
    if c == "{" then
      local t = {}
      pos = pos + 1; ws()
      if s:sub(pos, pos) == "}" then pos = pos + 1; return t end
      while true do
        ws()
        if s:sub(pos, pos) ~= '"' then fail("expected key") end
        local k = str(); ws()
        if s:sub(pos, pos) ~= ":" then fail("expected ':'") end
        pos = pos + 1
        t[k] = value(); ws()
        local d = s:sub(pos, pos); pos = pos + 1
        if d == "}" then return t elseif d ~= "," then fail("expected ',' or '}'") end
      end
    elseif c == "[" then
      local t = {}
      pos = pos + 1; ws()
      if s:sub(pos, pos) == "]" then pos = pos + 1; return t end
      while true do
        t[#t + 1] = value(); ws()
        local d = s:sub(pos, pos); pos = pos + 1
        if d == "]" then return t elseif d ~= "," then fail("expected ',' or ']'") end
      end
    elseif c == '"' then return str()
    elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
    elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
    elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
    end
    local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
    if not num or num == "" then fail("unexpected character '" .. c .. "'") end
    pos = pos + #num
    return tonumber(num)
  end

  local v = value()
  return v
end

-- returns value or nil, err   (never throws)
function J.try(s)
  local ok, v = pcall(J.decode, s)
  if ok then return v end
  return nil, v
end

return J
