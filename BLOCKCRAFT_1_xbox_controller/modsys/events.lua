-- Event bus. Mods subscribe with api.events.on(name, fn).
--   * A handler that returns false CANCELS the event (for cancellable events).
--   * A handler that errors is logged and skipped; it can never crash the game.
local E = {handlers = {}, log = print}

function E.on(name, fn, owner)
  assert(type(name) == "string", "event name must be a string")
  assert(type(fn) == "function", "event handler must be a function")
  local list = E.handlers[name]
  if not list then list = {}; E.handlers[name] = list end
  list[#list + 1] = {fn = fn, owner = owner or "?"}
end

-- returns false if any handler cancelled the event, otherwise true
function E.fire(name, ...)
  local list = E.handlers[name]
  if not list then return true end
  local ok = true
  for i = 1, #list do
    local h = list[i]
    local success, res = pcall(h.fn, ...)
    if not success then
      E.log(("[mod %s] error in '%s' handler: %s"):format(h.owner, name, tostring(res)))
    elseif res == false then
      ok = false
    end
  end
  return ok
end

-- like fire, but only calls the handlers that one mod registered
-- (used when a mod is added while the game is running)
function E.fireFor(owner, name, ...)
  local list = E.handlers[name]
  if not list then return end
  for i = 1, #list do
    local h = list[i]
    if h.owner == owner then
      local success, res = pcall(h.fn, ...)
      if not success then
        E.log(("[mod %s] error in '%s' handler: %s"):format(h.owner, name, tostring(res)))
      end
    end
  end
end

-- drop every handler registered by one mod
function E.removeOwner(owner)
  for _, list in pairs(E.handlers) do
    for i = #list, 1, -1 do
      if list[i].owner == owner then table.remove(list, i) end
    end
  end
end

return E
