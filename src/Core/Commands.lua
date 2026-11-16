-- Commands: parsing and routing for the /cforge slash command.
local _, ns = ...

local Commands = {}
Commands.__index = Commands
ns.Commands = Commands

function Commands.parse(text)
  local words = {}
  for word in tostring(text or ""):gmatch("%S+") do words[#words + 1] = word end
  local cmd = table.remove(words, 1)
  return { cmd = cmd and cmd:lower() or "", args = words }
end

--- @param handlers table of name -> function(args); "help" is the fallback.
function Commands.new(handlers)
  return setmetatable({ handlers = handlers }, Commands)
end

function Commands:run(text)
  local parsed = Commands.parse(text)
  local handler = self.handlers[parsed.cmd] or self.handlers.help
  if handler then handler(parsed.args) end
end
