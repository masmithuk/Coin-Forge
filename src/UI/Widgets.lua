-- Widgets: the small UI kit every ForeverGold screen is built from.
--
-- Design rules (see docs/ARCHITECTURE.md#ui):
--   * Flat dark panels, one accent colour (gold) for what matters: profit.
--   * Windows remember size and position, and everything inside reflows on resize.
--   * No button unless it does something the player can't do by clicking content.
local _, ns = ...

local Widgets = {}
ns.Widgets = Widgets

Widgets.COLORS = {
  bg = { 0.06, 0.06, 0.08, 0.95 },
  border = { 0.25, 0.25, 0.3, 1 },
  header = { 0.10, 0.10, 0.13, 1 },
  rowHover = { 1, 0.82, 0, 0.08 },
  gold = { 1, 0.82, 0 },
  text = { 0.92, 0.92, 0.92 },
  muted = { 0.55, 0.55, 0.6 },
  good = { 0.35, 0.9, 0.4 },
  bad = { 0.95, 0.35, 0.35 },
}
local C = Widgets.COLORS

local FLAT = { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }

function Widgets.skin(frame, bg)
  if frame.SetBackdrop then
    frame:SetBackdrop(FLAT)
    local b = bg or C.bg
    frame:SetBackdropColor(b[1], b[2], b[3], b[4])
    frame:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], C.border[4])
  end
end

function Widgets.text(parent, template, color)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
  local c = color or C.text
  fs:SetTextColor(c[1], c[2], c[3])
  fs:SetJustifyH("LEFT")
  return fs
end

--- Remembers a frame's size and position in `store` (a saved table).
local function persistGeometry(frame, store)
  if store.width then frame:SetSize(store.width, store.height) end
  if store.point then
    frame:ClearAllPoints()
    frame:SetPoint(store.point, UIParent, store.relativePoint or store.point, store.x or 0, store.y or 0)
  end
  frame.saveGeometry = function()
    store.width, store.height = frame:GetWidth(), frame:GetHeight()
    local point, _, relativePoint, x, y = frame:GetPoint()
    if point then store.point, store.relativePoint, store.x, store.y = point, relativePoint, x, y end
  end
end

--- Adds a bottom-right grip that resizes the frame within the given bounds.
function Widgets.makeResizable(frame, minW, minH, maxW, maxH)
  frame:SetResizable(true)
  if frame.SetResizeBounds then
    frame:SetResizeBounds(minW, minH, maxW, maxH)
  elseif frame.SetMinResize then
    frame:SetMinResize(minW, minH)
    frame:SetMaxResize(maxW, maxH)
  end
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    if frame.saveGeometry then frame.saveGeometry() end
  end)
  return grip
end

--- A movable, resizable window with a title and close button.
--- @param opts { name, title, width, height, minW, minH, store, parent }
function Widgets.window(opts)
  local f = CreateFrame("Frame", opts.name, opts.parent or UIParent, "BackdropTemplate")
  f:SetSize(opts.width, opts.height)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if self.saveGeometry then self.saveGeometry() end
  end)
  Widgets.skin(f)

  f.title = Widgets.text(f, "GameFontNormalLarge", C.gold)
  f.title:SetPoint("TOPLEFT", 12, -10)
  f.title:SetText(opts.title)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() f:Hide() end)

  Widgets.makeResizable(f, opts.minW, opts.minH, opts.maxW or 1400, opts.maxH or 1000)
  if opts.store then persistGeometry(f, opts.store) end
  -- close with Escape
  if opts.name and _G.UISpecialFrames then table.insert(_G.UISpecialFrames, opts.name) end
  return f
end

--- A row of text tabs that wraps onto new lines when the parent is narrow.
--- bar:SetTabs({ {kind, label, count, help} }, selectedKind); bar:GetHeight() after layout.
function Widgets.tabBar(parent, onSelect)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(20)
  bar.buttons = {}

  local function button(i)
    local b = bar.buttons[i]
    if b then return b end
    b = CreateFrame("Button", nil, bar)
    b:SetHeight(20)
    b.label = Widgets.text(b, "GameFontHighlightSmall")
    b.label:SetPoint("CENTER")
    b.underline = b:CreateTexture(nil, "ARTWORK")
    b.underline:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    b.underline:SetPoint("BOTTOMLEFT", 4, 0)
    b.underline:SetPoint("BOTTOMRIGHT", -4, 0)
    b.underline:SetHeight(2)
    b:SetScript("OnClick", function(self)
      -- show the new selection straight away; don't rely on the owner redrawing
      bar:SetTabs(bar.tabs, self.kind)
      onSelect(self.kind)
    end)
    b:SetScript("OnEnter", function(self)
      if not self.help then return end
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:SetText(self.help, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.buttons[i] = b
    return b
  end

  function bar:SetTabs(tabs, selected)
    self.tabs, self.selected = tabs, selected
    for i, tab in ipairs(tabs) do
      local b = button(i)
      b.kind, b.help = tab.kind, tab.help
      b.label:SetText(tab.count and (tab.label .. " " .. tab.count) or tab.label)
      local active = tab.kind == selected
      local c = active and C.gold or C.muted
      b.label:SetTextColor(c[1], c[2], c[3])
      b.underline:SetShown(active)
      b:SetWidth(b.label:GetStringWidth() + 16)
      b:Show()
    end
    for i = #tabs + 1, #self.buttons do self.buttons[i]:Hide() end
    self:Reflow()
  end

  function bar:Reflow()
    local width = math.max(self:GetWidth(), 50)
    local x, y = 0, 0
    for i = 1, #(self.tabs or {}) do
      local b = self.buttons[i]
      local w = b:GetWidth()
      if x > 0 and x + w > width then x, y = 0, y + 20 end
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", x, -y)
      x = x + w
    end
    self:SetHeight(y + 20)
  end

  bar:SetScript("OnSizeChanged", function(self) self:Reflow() end)
  return bar
end

--- A virtual list: only as many row frames as fit, scrolled with the mouse wheel.
--- @param opts {
---   columns = { {key, title, min, weight, priority, justify} },
---   rowHeight, onClick(item, button), onEnter(rowFrame, item),
---   cells(item) -> { [key] = text }, color(item) -> {r,g,b} or nil,
---   emptyText() -> string }
function Widgets.list(parent, opts)
  local HEADER = 18
  local rowHeight = opts.rowHeight or 18
  local list = CreateFrame("Frame", nil, parent)
  list.items, list.offset, list.rows = {}, 0, {}

  list.header = CreateFrame("Frame", nil, list, "BackdropTemplate")
  list.header:SetPoint("TOPLEFT")
  list.header:SetPoint("TOPRIGHT")
  list.header:SetHeight(HEADER)
  Widgets.skin(list.header, C.header)
  list.header.cells = {}
  for _, col in ipairs(opts.columns) do
    local fs = Widgets.text(list.header, "GameFontNormalSmall", C.muted)
    fs:SetText(col.title)
    fs:SetJustifyH(col.justify or "LEFT")
    list.header.cells[col.key] = fs
  end

  list.empty = Widgets.text(list, "GameFontHighlight", C.muted)
  list.empty:SetPoint("TOPLEFT", 12, -HEADER - 16)
  list.empty:SetPoint("RIGHT", -12, 0)
  list.empty:SetJustifyH("CENTER")
  list.empty:SetWordWrap(true)

  list.thumb = list:CreateTexture(nil, "OVERLAY")
  list.thumb:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.5)
  list.thumb:SetWidth(3)

  local function row(i)
    local r = list.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, list)
    r:SetHeight(rowHeight)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.hover = r:CreateTexture(nil, "BACKGROUND")
    r.hover:SetAllPoints()
    r.hover:SetColorTexture(C.rowHover[1], C.rowHover[2], C.rowHover[3], C.rowHover[4])
    r.hover:Hide()
    r.cells = {}
    for _, col in ipairs(opts.columns) do
      local fs = Widgets.text(r, "GameFontHighlightSmall")
      fs:SetJustifyH(col.justify or "LEFT")
      fs:SetWordWrap(false)
      r.cells[col.key] = fs
    end
    r:SetScript("OnEnter", function(self)
      self.hover:Show()
      if opts.onEnter and self.item then opts.onEnter(self, self.item) end
    end)
    r:SetScript("OnLeave", function(self)
      self.hover:Hide()
      GameTooltip:Hide()
    end)
    r:SetScript("OnClick", function(self, mouse)
      if opts.onClick and self.item then opts.onClick(self.item, mouse) end
    end)
    list.rows[i] = r
    return r
  end

  function list:Layout()
    local width, height = self:GetWidth(), self:GetHeight()
    self.visibleCols = ns.Layout.columns(width - 14, opts.columns)
    self.visibleCount = ns.Layout.visibleRows(height, rowHeight, HEADER)
    local shown = {}
    for _, col in ipairs(self.visibleCols) do shown[col.key] = col end
    for key, fs in pairs(self.header.cells) do
      local col = shown[key]
      fs:SetShown(col ~= nil)
      if col then
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", self.header, "LEFT", 6 + col.x, 0)
        fs:SetWidth(col.width - 6)
      end
    end
    for i = 1, self.visibleCount do
      local r = row(i)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 0, -HEADER - (i - 1) * rowHeight)
      r:SetPoint("RIGHT", -6, 0)
      for key, fs in pairs(r.cells) do
        local col = shown[key]
        fs:SetShown(col ~= nil)
        if col then
          fs:ClearAllPoints()
          fs:SetPoint("LEFT", r, "LEFT", 6 + col.x, 0)
          fs:SetWidth(col.width - 6)
        end
      end
    end
    self:Refresh()
  end

  function list:Refresh()
    local count = #self.items
    local visible = self.visibleCount or 0
    self.offset = math.max(0, math.min(self.offset, count - visible))
    for i, r in ipairs(self.rows) do
      local item = i <= visible and self.items[self.offset + i] or nil
      r.item = item
      if item then
        local cells = opts.cells(item)
        local color = opts.color and opts.color(item)
        for key, fs in pairs(r.cells) do
          fs:SetText(cells[key] or "")
          local c = (color and color[key]) or (key == "profit" and C.gold) or C.text
          fs:SetTextColor(c[1], c[2], c[3])
        end
        r:Show()
      else
        r:Hide()
      end
    end
    self.empty:SetShown(count == 0)
    if count == 0 and opts.emptyText then self.empty:SetText(opts.emptyText()) end
    -- slim scroll position indicator
    if count > visible and visible > 0 then
      local track = self:GetHeight() - HEADER
      local size = math.max(12, track * visible / count)
      local pos = (track - size) * self.offset / (count - visible)
      self.thumb:ClearAllPoints()
      self.thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", -1, -HEADER - pos)
      self.thumb:SetHeight(size)
      self.thumb:Show()
    else
      self.thumb:Hide()
    end
  end

  function list:SetItems(items)
    self.items = items or {}
    -- lay out on first use; afterwards OnSizeChanged keeps it in step
    if not self.visibleCount then self:Layout() else self:Refresh() end
  end

  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(self, delta)
    self.offset = self.offset - delta * 3
    self:Refresh()
  end)
  list:SetScript("OnSizeChanged", function(self) self:Layout() end)
  return list
end
