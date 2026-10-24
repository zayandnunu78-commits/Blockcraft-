-- ============================================================
-- mesher.lua - turns chunks into meshes (one mesh per 16x16x16 chunk).
--
-- Speed tricks, in the order they help:
--   * only faces you could see are built (a face between two solid blocks is skipped,
--     also across chunk borders)
--   * a chunk that is all air gets no mesh; a solid chunk with solid neighbours gets none either
--   * a chunk is only meshed once its 6 neighbours are loaded (otherwise its border faces
--     would be wrong); it is re-queued automatically when a neighbour appears
--   * dirty chunks are rebuilt nearest-first, with a time budget per frame
--   * vertex tables are recycled (a mesh build makes almost no garbage)
--   * mesh vertices are chunk-local (0..16) and the chunk's position is a model
--     transform, so far from the middle of the world nothing jitters
--   * drawing skips chunks outside the camera's view cone
-- ============================================================
local g3d = require "g3d"
local world = require "world"
local blocks = require "blocks"
local faces = require "faces"
local textures = require "textures"

local M = {models = {}, drawn = 0, culled = 0, built = 0}
local CS, CZ = world.CS, world.CZ
local CS2 = CS * CS
local order = {1, 2, 3, 1, 3, 4}
local cornerUV = {{0, 1}, {1, 1}, {1, 0}, {0, 0}}
M.clock = function() return love.timer.getTime() end -- (tests replace this)

local d = love.image.newImageData(1, 1)
d:setPixel(0, 0, 1, 1, 1, 1)
local tex = love.graphics.newImage(d)

-- ---------- recycled vertex tables ----------
local pool, used = {}, 0
local scratch, scratchN = {}, 0

local function vertex(x, y, z, u, v, nx, ny, nz, s)
  used = used + 1
  local t = pool[used]
  if not t then t = {}; pool[used] = t end
  t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8] = x, y, z, u, v, nx, ny, nz
  t[9], t[10], t[11], t[12] = s, s, s, 1
  scratch[used] = t
end

-- uv corners of a tile: uvTable[tile] = {u0, u1, v0, v1} (rebuilt when the atlas changes)
local uvTable, uvVersion = {}, -1
local function tileUV(tile)
  if uvVersion ~= textures.version then uvTable, uvVersion = {}, textures.version end
  local t = uvTable[tile]
  if not t then
    local u0, v0 = textures.uv(tile, 0, 0)
    local u1, v1 = textures.uv(tile, 1, 1)
    t = {u0, u1, v0, v1}
    uvTable[tile] = t
  end
  return t
end

-- stand-ins for "outside the world"
local SOLID = {fill = 1}   -- below the world: no faces
local AIR = {fill = 0}     -- above the world

local function nbSolid(n, idx)
  local b = n.blocks
  if b then return b[idx] ~= 0 end
  return n.fill ~= 0
end

-- all 6 face-neighbours loaded? (vertical neighbours outside the world count as loaded)
local function neighboursLoaded(c)
  local chunks, cx, cy, cz = world.chunks, c.cx, c.cy, c.cz
  if not (chunks[world.key(cx - 1, cy, cz)] and chunks[world.key(cx + 1, cy, cz)]
      and chunks[world.key(cx, cy - 1, cz)] and chunks[world.key(cx, cy + 1, cz)]) then
    return false
  end
  if cz > 0 and not chunks[world.key(cx, cy, cz - 1)] then return false end
  if cz < CZ - 1 and not chunks[world.key(cx, cy, cz + 1)] then return false end
  return true
end

function M.release(key)
  local e = M.models[key]
  if e then
    if e.m.mesh and e.m.mesh.release then pcall(e.m.mesh.release, e.m.mesh) end
    M.models[key] = nil
  end
end

function M.clear()
  for key in pairs(M.models) do M.release(key) end
  M.models = {}
end

local function build(c)
  M.release(c.key)
  local cx, cy, cz = c.cx, c.cy, c.cz
  local chunks = world.chunks
  local bl, fill = c.blocks, c.fill
  if not bl and fill == 0 then return end

  local nxm = chunks[world.key(cx - 1, cy, cz)] or SOLID
  local nxp = chunks[world.key(cx + 1, cy, cz)] or SOLID
  local nym = chunks[world.key(cx, cy - 1, cz)] or SOLID
  local nyp = chunks[world.key(cx, cy + 1, cz)] or SOLID
  local nzm = (cz > 0) and (chunks[world.key(cx, cy, cz - 1)] or SOLID) or SOLID
  local nzp = (cz < CZ - 1) and (chunks[world.key(cx, cy, cz + 1)] or SOLID) or AIR

  -- a solid chunk buried in solid chunks has nothing to show
  if not bl then
    local function allSolid(n) return not n.blocks and n.fill ~= 0 end
    if allSolid(nxm) and allSolid(nxp) and allSolid(nym) and allSolid(nyp)
       and allSolid(nzm) and allSolid(nzp) then
      return
    end
  end

  used = 0
  local x0, y0, z0 = c.x0, c.y0, c.z0
  for lz = 0, CS - 1 do
    for ly = 0, CS - 1 do
      for lx = 0, CS - 1 do
        local id
        if bl then id = bl[lx + ly * CS + lz * CS2 + 1] else id = fill end
        if id ~= 0 then
          local def = blocks[id]
          if def then
            local x, y, z = x0 + lx, y0 + ly, z0 + lz
            local shade = ((x * 37 + y * 57 + z * 91 + x * y * 13) % 17) / 17 * 0.12 - 0.06
            for fi = 1, 6 do
              local f = faces[fi]
              local n = f.n
              local nx, ny, nz = n[1], n[2], n[3]
              local ax, ay, az = lx + nx, ly + ny, lz + nz
              local hidden
              if ax >= 0 and ax < CS and ay >= 0 and ay < CS and az >= 0 and az < CS then
                if bl then hidden = bl[ax + ay * CS + az * CS2 + 1] ~= 0 else hidden = fill ~= 0 end
              elseif ax < 0 then hidden = nbSolid(nxm, 15 + ly * CS + lz * CS2 + 1)
              elseif ax >= CS then hidden = nbSolid(nxp, 0 + ly * CS + lz * CS2 + 1)
              elseif ay < 0 then hidden = nbSolid(nym, lx + 15 * CS + lz * CS2 + 1)
              elseif ay >= CS then hidden = nbSolid(nyp, lx + 0 * CS + lz * CS2 + 1)
              elseif az < 0 then hidden = nbSolid(nzm, lx + ly * CS + 15 * CS2 + 1)
              else hidden = nbSolid(nzp, lx + ly * CS + 0 * CS2 + 1) end

              if not hidden then
                local t = def.side
                if nz == 1 then t = def.top elseif nz == -1 then t = def.bottom end
                local uv = tileUV(t)
                local s = f.s + shade
                if s > 1 then s = 1 end
                local fv = f.v
                for i = 1, 6 do
                  local ci = order[i]
                  local p, cuv = fv[ci], cornerUV[ci]
                  vertex(lx + p[1], ly + p[2], lz + p[3],
                         uv[1 + cuv[1]], uv[3 + cuv[2]], nx, ny, nz, s)
                end
              end
            end
          end
        end
      end
    end
  end

  -- the scratch list must end exactly after the last vertex (it is reused)
  for i = used + 1, scratchN do scratch[i] = nil end
  scratchN = used
  M.built = M.built + 1
  if used == 0 then return end

  local m = g3d.newModel(scratch, textures.image)
  m.verts = nil -- we recycle those tables; the GPU already has a copy
  m:setTransform({x0, y0, z0}, {0, 0, 0}, {1, 1, 1})
  M.models[c.key] = {m = m, mx = x0 + CS / 2, my = y0 + CS / 2, mz = z0 + CS / 2, verts = used}
end

M._build = build -- exposed for tests

-- Rebuild dirty chunks, nearest to (px, py, pz) first, until `budget` seconds are used
-- (at least one chunk per call). Returns how many were built.
function M.update(px, py, pz, budget)
  if next(world.dirty) == nil then return 0 end
  px, py, pz = px or 0, py or 0, pz or 0
  budget = budget or 0.004

  local list, n = {}, 0
  for _, c in pairs(world.dirty) do
    local dx, dy, dz = c.x0 + 8 - px, c.y0 + 8 - py, c.z0 + 8 - pz
    c.d2 = dx * dx + dy * dy + dz * dz
    n = n + 1
    list[n] = c
  end
  table.sort(list, function(a, b) if a.d2 ~= b.d2 then return a.d2 < b.d2 end return a.key < b.key end)

  local t0, built = M.clock(), 0
  for i = 1, n do
    local c = list[i]
    world.dirty[c.key] = nil
    if world.chunks[c.key] == c and neighboursLoaded(c) then
      build(c)
      built = built + 1
      if M.clock() - t0 >= budget then break end
    end
    -- chunks still missing a neighbour are dropped from the list: world.addChunk marks
    -- them dirty again the moment that neighbour arrives
  end
  return built
end

-- ---------- drawing ----------
local SPHERE = CS * 0.8660254 -- radius of a sphere around a chunk
local sqrt, acos, asin = math.sqrt, math.acos, math.asin

function M.draw()
  local cam = g3d.camera
  local ex, ey, ez = cam.position[1], cam.position[2], cam.position[3]
  local fx, fy, fz = cam.target[1] - ex, cam.target[2] - ey, cam.target[3] - ez
  local fl = sqrt(fx * fx + fy * fy + fz * fz)
  if fl == 0 then fl = 1 end
  fx, fy, fz = fx / fl, fy / fl, fz / fl
  local tv = math.tan((cam.fov or 1.5) / 2)
  local th = tv * (cam.aspectRatio or 1.5)
  local half = math.atan(sqrt(tv * tv + th * th)) -- half of the view cone's widest angle

  local drawn, culled = 0, 0
  for _, e in pairs(M.models) do
    local dx, dy, dz = e.mx - ex, e.my - ey, e.mz - ez
    local dist = sqrt(dx * dx + dy * dy + dz * dz)
    local visible = dist <= SPHERE
    if not visible then
      local cosA = (dx * fx + dy * fy + dz * fz) / dist
      if cosA > 1 then cosA = 1 elseif cosA < -1 then cosA = -1 end
      visible = acos(cosA) <= half + asin(SPHERE / dist)
    end
    if visible then e.m:draw(); drawn = drawn + 1 else culled = culled + 1 end
  end
  M.drawn, M.culled = drawn, culled
end

-- a faint dark cube around the block you are aiming at
local hl
function M.highlight(x, y, z)
  if not hl then
    local v = {}
    for _, f in ipairs(faces) do
      for i = 1, 6 do
        local p = f.v[order[i]]
        v[#v + 1] = {p[1], p[2], p[3], 0, 0, f.n[1], f.n[2], f.n[3], 0, 0, 0, 0.3}
      end
    end
    hl = g3d.newModel(v, tex)
  end
  hl:setTransform({x - .005, y - .005, z - .005}, {0, 0, 0}, {1.01, 1.01, 1.01})
  hl:draw()
end

return M
