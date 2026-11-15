-- Events: a tiny publish/subscribe bus used to decouple modules
-- (e.g. the scanner announces "scanComplete" and the UI refreshes).
local _, ns = ...

local Events = {}
Events.__index = Events
ns.Events = Events

function Events.new()
  return setmetatable({ handlers = {} }, Events)
end

--- Subscribes to an event. Returns a function that unsubscribes.
function Events:on(name, handler)
  local list = self.handlers[name] or {}
  self.handlers[name] = list
  list[#list + 1] = handler
  return function()
    for i = #list, 1, -1 do
      if list[i] == handler then table.remove(list, i) end
    end
  end
end

function Events:emit(name, ...)
  local list = self.handlers[name]
  if not list then return end
  -- copy so handlers may unsubscribe while we iterate
  local snapshot = { unpack(list) }
  for _, handler in ipairs(snapshot) do handler(...) end
end
