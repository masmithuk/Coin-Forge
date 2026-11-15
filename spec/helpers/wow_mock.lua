-- A minimal fake of the WoW client for adapter and UI tests.
--
-- Frames: any method call is accepted. Calls are recorded in frame.calls and a
-- few methods (Show/Hide/SetText/SetScript...) keep state so tests can assert.
-- Scripts set with SetScript can be fired with frame:Fire("OnClick", ...).

local M = {}

local Frame = {}

local stateful = {
  Show = function(self) self.shown = true end,
  Hide = function(self) self.shown = false end,
  IsShown = function(self) return self.shown == true end,
  IsVisible = function(self) return self.shown == true end,
  SetShown = function(self, v) self.shown = v and true or false end,
  SetText = function(self, t) self.text = t end,
  GetText = function(self) return self.text end,
  SetScript = function(self, name, fn) self.scripts[name] = fn end,
  GetScript = function(self, name) return self.scripts[name] end,
  HookScript = function(self, name, fn)
    local prev = self.scripts[name]
    self.scripts[name] = function(...) if prev then prev(...) end fn(...) end
  end,
  SetWidth = function(self, w) self.width = w end,
  SetHeight = function(self, h) self.height = h end,
  SetSize = function(self, w, h) self.width, self.height = w, h end,
  GetWidth = function(self) return self.width or 300 end,
  GetHeight = function(self) return self.height or 300 end,
  Enable = function(self) self.enabled = true end,
  Disable = function(self) self.enabled = false end,
  IsEnabled = function(self) return self.enabled ~= false end,
  SetEnabled = function(self, v) self.enabled = v and true or false end,
  SetChecked = function(self, v) self.checked = v end,
  GetChecked = function(self) return self.checked end,
  RegisterEvent = function(self, e)
    -- Like the retail-based client (WoW Forever): unknown event names are a hard error.
    if M.validEvents and not M.validEvents[e] then
      error('Attempt to register unknown event "' .. tostring(e) .. '"', 2)
    end
    self.events[e] = true
  end,
  UnregisterEvent = function(self, e) self.events[e] = nil end,
  GetName = function(self) return self.name end,
  GetParent = function(self) return self.parent end,
  GetStringWidth = function(self) return #(self.text or "") * 6 end,
  CreateTexture = function(self) return M.frame(self) end,
  CreateFontString = function(self)
    local fs = M.frame(self)
    if M.track then M.track[#M.track + 1] = fs end
    return fs
  end,
  CreateAnimationGroup = function(self) return M.frame(self) end,
  CreateAnimation = function(self) return M.frame(self) end,
  GetObjectType = function() return "Frame" end,
  Fire = function(self, name, ...)
    local fn = self.scripts[name]
    if fn then return fn(self, ...) end
  end,
}

-- Verb prefixes of real widget methods. Other unknown keys read as nil, like a
-- real frame, so code can store its own fields (frame.myChild) on frames.
local VERBS = {
  "Set", "Get", "Is", "Enable", "Disable", "Clear", "Register", "Unregister", "Add", "Start", "Stop",
  "Play", "Lower", "Raise", "Click", "Lock", "Unlock", "Update", "Highlight", "Unhighlight",
  "Make", "Has", "Can", "Save", "Refresh", "Adjust", "Reset", "Set",
}

local function isMethodName(key)
  if type(key) ~= "string" then return false end
  for _, verb in ipairs(VERBS) do
    if key == verb then return true end
    if key:sub(1, #verb) == verb and key:sub(#verb + 1, #verb + 1):match("[A-Z%d]") then return true end
  end
  return false
end

Frame.__index = function(_, key)
  if stateful[key] then return stateful[key] end
  if not isMethodName(key) then return nil end
  -- unknown widget method: accept and record the call
  return function(frame, ...)
    frame.calls[#frame.calls + 1] = { key, ... }
    return nil
  end
end

function M.frame(parent, name)
  return setmetatable({ calls = {}, scripts = {}, events = {}, parent = parent, name = name }, Frame)
end

--- Installs a fake WoW global environment into _G and returns it.
-- Pass overrides to replace or add API functions. Call M.uninstall() after.
function M.install(overrides)
  local env = {}
  local created = {}
  env.CreateFrame = function(_, name, parent)
    local f = M.frame(parent, name)
    created[#created + 1] = f
    if name then
      env[name] = f
      rawset(_G, name, f)
      M.created = M.created or {}
      M.created[#M.created + 1] = name
    end
    return f
  end
  env.__created = created
  M.track = created
  env.UIParent = M.frame(nil, "UIParent")
  env.GameTooltip = M.frame(env.UIParent, "GameTooltip")
  env.Minimap = M.frame(env.UIParent, "Minimap")
  env.hooksecurefunc = function(a, b, c)
    local tbl, name, fn = a, b, c
    if type(a) == "string" then tbl, name, fn = env, a, b end
    local orig = tbl[name]
    tbl[name] = function(...)
      local r = orig and orig(...)
      fn(...)
      return r
    end
  end
  env.C_Timer = {
    After = function(_, fn) fn() end,
    NewTicker = function(_, fn) return { Cancel = function() end, fn = fn } end,
  }
  env.GetTime = function() return 1000 end
  env.time = os.time
  env.date = os.date
  env.GetMoney = function() return 0 end
  env.GetRealmName = function() return "Forever" end
  env.UnitFactionGroup = function() return "Horde" end
  env.GetSubZoneText = function() return "" end
  env.GetZoneText = function() return "Orgrimmar" end
  env.UnitFullName = function() return "Thrall", "Forever" end
  env.UnitName = function() return "Thrall" end
  env.UnitGUID = function() return nil end
  env.UnitIsPlayer = function() return false end
  env.UnitIsDead = function() return false end
  env.GetItemInfo = function() return nil end
  env.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  env.ITEM_QUALITY_COLORS = setmetatable({}, { __index = function() return { hex = "|cffffffff" } end })
  env.SlashCmdList = {}
  env.Enum = { TooltipDataType = { Item = 0, Unit = 2 } }
  for k, v in pairs(overrides or {}) do env[k] = v end

  M.saved = {}
  for k, v in pairs(env) do
    M.saved[k] = { value = rawget(_G, k) }
    rawset(_G, k, v)
  end
  return env
end

function M.uninstall()
  for k, v in pairs(M.saved or {}) do rawset(_G, k, v.value) end
  for _, name in ipairs(M.created or {}) do rawset(_G, name, nil) end
  M.saved, M.created = nil, nil
end

return M
