-- ============================================================
-- emotes.lua - the 5 emotes (little pixel pictures). There is NO typing:
-- a player can only pick a number from 1 to 5, so emotes can never carry words.
-- Each picture is drawn as a floating pixel sign above a player (3D) and as a
-- small icon on the buttons (2D). Keep emotes.count the same as P.EMOTE_COUNT
-- in net/protocol.lua.
-- ============================================================
local g3d = require "g3d"
local faces = require "faces"

local E = {}

E.names = {"Heart", "Star", "Smile", "Thumbs up", "Diamond"}

-- letters pick a colour, "." is empty
local colors = {
  R = {0.95, 0.2, 0.25}, Y = {1.0, 0.85, 0.2}, K = {0.2, 0.15, 0.1},
  B = {0.3, 0.85, 1.0}, S = {1.0, 0.8, 0.6}, W = {1, 1, 1},
}

local art = {
  { ".RR.RR.",
    "RWRRRRR",
    "RRRRRRR",
    ".RRRRR.",
    "..RRR..",
    "...R..." },
  { "...Y...",
    "...Y...",
    "YYYYYYY",
    ".YYYYY.",
    "..YYY..",
    ".YY.YY.",
    "YY...YY" },
  { ".YYYYY.",
    "YYYYYYY",
    "YKYYYKY",
    "YYYYYYY",
    "YKYYYKY",
    "YYKKKYY",
    ".YYYYY." },
  { "...SS..",
    "...SS..",
    "..SSS..",
    "SSSSSSS",
    "SSSSSSS",
    "SSSSSSS",
    ".SSSSS." },
  { ".BBBBB.",
    "BWBBBBB",
    ".BBBBB.",
    "..BBB..",
    "...B..." },
}

E.count = #art

local order = {1, 2, 3, 1, 3, 4}
local white
local models = {}

local function addBox(verts, x0, y0, z0, x1, y1, z1, c)
  for _, f in ipairs(faces) do
    for i = 1, 6 do
      local p = f.v[order[i]]
      verts[#verts + 1] = {x0 + p[1] * (x1 - x0), y0 + p[2] * (y1 - y0), z0 + p[3] * (z1 - z0),
                           0, 0, f.n[1], f.n[2], f.n[3],
                           c[1] * f.s, c[2] * f.s, c[3] * f.s, 1}
    end
  end
end

-- 3D model of emote `id`. Its picture faces +x, and is centred on the origin sideways.
function E.model(id)
  if not models[id] then
    if not white then
      local d = love.image.newImageData(1, 1)
      d:setPixel(0, 0, 1, 1, 1, 1)
      white = love.graphics.newImage(d)
    end
    local rows = art[id]
    local ps = 0.09
    local w, h = #rows[1], #rows
    local verts = {}
    for r = 1, h do
      for c = 1, w do
        local color = colors[rows[r]:sub(c, c)]
        if color then
          addBox(verts, -0.025, (c - 1 - w / 2) * ps, (h - r) * ps,
                        0.025, (c - w / 2) * ps, (h - r + 1) * ps, color)
        end
      end
    end
    models[id] = g3d.newModel(verts, white)
  end
  return models[id]
end

-- flat picture for the buttons: top-left corner (x, y), size in pixels
function E.draw2d(id, x, y, size, alpha)
  local rows = art[id]
  local w, h = #rows[1], #rows
  local ps = size / math.max(w, h)
  local ox, oy = x + (size - w * ps) / 2, y + (size - h * ps) / 2
  for r = 1, h do
    for c = 1, w do
      local color = colors[rows[r]:sub(c, c)]
      if color then
        love.graphics.setColor(color[1], color[2], color[3], alpha or 1)
        love.graphics.rectangle("fill", ox + (c - 1) * ps, oy + (r - 1) * ps, ps + 0.5, ps + 0.5)
      end
    end
  end
end

return E
