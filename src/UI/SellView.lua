-- SellView: the Sell tab of the auction panel.
--
--   ┌ list: everything in your bags you can auction, most valuable first ┐
--   │ Item              Qty   Price each   Total    Advice              │
--   └────────────────────────────────────────────────────────────────────┘
--   ┌ detail (shown once you pick a row) ─────────────────────────────────┐
--   │ [icon] Item name x20                                   [  Post  ]  │
--   │ Why this price (bait ignored, price war, undercut...)               │
--   │ Price each [ 1g 2s 3c ]  Qty [ 20 ] / 20   2 h | 8 h | 24 h         │
--   │ Total 20g 4s · you get 19g 3s after the cut · deposit 15s           │
--   └─────────────────────────────────────────────────────────────────────┘
--
-- Picking a row fills in the suggestion straight away from the last scan, then
-- a live search refines it. Every field stays editable; Post (or Enter in a
-- field) creates the auction and moves on to the next item.
local _, ns = ...

local SellView = {}
SellView.__index = SellView
ns.SellView = SellView

local W, Money = ns.Widgets, ns.Money
local C = ns.Widgets.COLORS
local DETAIL_HEIGHT = 112

local COLUMNS = {
  { key = "name", title = "Item", min = 110, weight = 4, priority = 1 },
  { key = "qty", title = "Qty", min = 34, weight = 0, priority = 3, justify = "RIGHT" },
  { key = "price", title = "Price each", min = 70, weight = 1, priority = 1, justify = "RIGHT" },
  { key = "total", title = "Total", min = 70, weight = 1, priority = 2, justify = "RIGHT" },
  { key = "advice", title = "Advice", min = 70, weight = 1, priority = 4 },
}

local ADVICE = {
  post = { "Post", C.good },
  vendor = { "Vendor it", C.gold },
  manual = { "Set a price", C.muted },
}

function SellView.new(app, parent)
  local self = setmetatable({ app = app, rows = {} }, SellView)
  self.store = app.db.ui.sell or {}
  app.db.ui.sell = self.store
  self.duration = self.store.duration or app.settings.sellDuration
  self:Build(parent)
  app.events:on("sellSuggestion", function(item, suggestion, live)
    if self.selected and self.selected.item.key == item.key then self:ApplySuggestion(suggestion, live) end
  end)
  return self
end

local function input(parent, width, numeric)
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  box:SetSize(width, 20)
  box:SetAutoFocus(false)
  box:SetFontObject("GameFontHighlightSmall")
  if numeric then box:SetNumeric(true) end
  box:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
  return box
end

function SellView:Build(parent)
  self.list = W.list(parent, {
    columns = COLUMNS,
    cells = function(r)
      local s = r.suggestion
      return {
        name = ns.ItemInfo.name(r.item.itemID) or r.item.link or "?",
        qty = tostring(r.item.postable),
        price = s.price and Money.short(s.price) or "?",
        total = s.price and Money.short(r.total) or "",
        advice = ADVICE[s.action][1],
      }
    end,
    color = function(r)
      local c = { advice = ADVICE[r.suggestion.action][2] }
      if self.selected and self.selected.item.key == r.item.key then c.name = C.gold end
      return c
    end,
    onClick = function(r) self:Select(r) end,
    onEnter = function(row, r)
      GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
      if GameTooltip.SetHyperlink and r.item.link then GameTooltip:SetHyperlink(r.item.link) end
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(r.suggestion.reason or "", 1, 1, 1, true)
      GameTooltip:AddLine("Click to set it up for posting", 0.5, 0.5, 0.5)
      GameTooltip:Show()
    end,
    emptyText = function() return "Nothing in your bags can be sold on the auction house." end,
  })

  local d = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  self.detail = d
  d:SetHeight(DETAIL_HEIGHT)
  W.skin(d, C.header)
  d:Hide()

  self.icon = d:CreateTexture(nil, "ARTWORK")
  self.icon:SetSize(28, 28)
  self.icon:SetPoint("TOPLEFT", 8, -8)
  self.title = W.text(d, "GameFontNormal", C.gold)
  self.title:SetPoint("LEFT", self.icon, "RIGHT", 6, 0)
  self.title:SetPoint("RIGHT", -110, 0)
  self.title:SetWordWrap(false)

  self.post = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
  self.post:SetSize(90, 24)
  self.post:SetPoint("TOPRIGHT", -8, -10)
  self.post:SetText("Post")
  self.post:SetScript("OnClick", function() self:Post() end)

  self.reason = W.text(d, "GameFontHighlightSmall", C.muted)
  self.reason:SetPoint("TOPLEFT", self.icon, "BOTTOMLEFT", 0, -4)
  self.reason:SetPoint("RIGHT", -8, 0)
  self.reason:SetWordWrap(true)
  self.reason:SetHeight(24)

  local priceLabel = W.text(d, "GameFontHighlightSmall")
  priceLabel:SetPoint("TOPLEFT", self.reason, "BOTTOMLEFT", 0, -6)
  priceLabel:SetText("Price each")
  self.price = input(d, 96)
  self.price:SetPoint("LEFT", priceLabel, "RIGHT", 8, 0)

  local qtyLabel = W.text(d, "GameFontHighlightSmall")
  qtyLabel:SetPoint("LEFT", self.price, "RIGHT", 12, 0)
  qtyLabel:SetText("Qty")
  self.qty = input(d, 40, true)
  self.qty:SetPoint("LEFT", qtyLabel, "RIGHT", 8, 0)
  self.qtyMax = W.text(d, "GameFontHighlightSmall", C.muted)
  self.qtyMax:SetPoint("LEFT", self.qty, "RIGHT", 4, 0)

  self.durations = W.tabBar(d, function(value)
    self.duration = value
    self.store.duration = value
    self:UpdateTotals()
  end)
  self.durations:SetPoint("LEFT", self.qtyMax, "RIGHT", 12, 0)
  self.durations:SetPoint("RIGHT", d, "RIGHT", -8, 0)

  self.totals = W.text(d, "GameFontHighlightSmall")
  self.totals:SetPoint("BOTTOMLEFT", 8, 8)
  self.totals:SetPoint("RIGHT", -8, 0)
  self.totals:SetWordWrap(false)

  for _, box in ipairs({ self.price, self.qty }) do
    box:SetScript("OnTextChanged", function(_, userInput) if userInput then self:UpdateTotals() end end)
    box:SetScript("OnEnterPressed", function(b) b:ClearFocus() self:Post() end)
  end
end

-- Placement inside the panel's content area (top-left to bottom-right anchors).
function SellView:SetArea(topLeftFrame, bottomRightFrame)
  self.area = { topLeftFrame, bottomRightFrame }
  self:Layout()
end

function SellView:Layout()
  if not self.area then return end
  local top, bottom = self.area[1], self.area[2]
  self.detail:ClearAllPoints()
  self.detail:SetPoint("BOTTOMLEFT", bottom, "BOTTOMLEFT", 8, 26)
  self.detail:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT", -8, 26)
  self.list:ClearAllPoints()
  self.list:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -4)
  if self.detail:IsShown() then
    self.list:SetPoint("BOTTOMRIGHT", self.detail, "TOPRIGHT", 0, 4)
  else
    self.list:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT", -8, 26)
  end
end

function SellView:SetShown(shown)
  self.list:SetShown(shown)
  self.detail:SetShown(shown and self.selected ~= nil)
  if shown then self:Refresh() end
end

function SellView:Refresh()
  local key = self.selected and self.selected.item.key
  self.rows = self.app:sellRows()
  self.selected = nil
  for _, r in ipairs(self.rows) do
    if r.item.key == key then self.selected = r end
  end
  self.list:SetItems(self.rows)
  self.detail:SetShown(self.list:IsShown() and self.selected ~= nil)
  self:Layout()
  if self.selected then self:UpdateTotals() end
end

function SellView:Select(row)
  self.selected = row
  local item = row.item
  local info = ns.ItemInfo.get(item.itemID)
  self.icon:SetTexture(info and info.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
  self.title:SetText(("%s  x%d"):format(info and info.name or item.link or "?", item.postable))
  self.qty:SetText(tostring(item.postable))
  self.qtyMax:SetText("/ " .. item.postable)
  local tabs = {}
  for _, d in ipairs(ns.Poster.DURATIONS) do tabs[#tabs + 1] = { kind = d.value, label = d.label } end
  self.durations:SetTabs(tabs, self.duration)
  self:ApplySuggestion(row.suggestion, false)
  self.detail:Show()
  self:Layout()
  self.list:Refresh()
  self.app.sellSearch:request(item)
end

function SellView:ApplySuggestion(s, live)
  self.suggestion = s
  self.price:SetText(s.price and Money.format(s.price) or "")
  local source = live and "Live prices. " or "From your last scan, checking live prices... "
  self.reason:SetText(source .. (s.reason or ""))
  self:UpdateTotals()
end

function SellView:Values()
  local price = Money.parse(self.price:GetText())
  local qty = tonumber(self.qty:GetText())
  return price, qty
end

function SellView:UpdateTotals()
  local row = self.selected
  if not row then return end
  local price, qty = self:Values()
  local valid = price and price > 0 and qty and qty > 0 and qty <= row.item.postable
  if not valid then
    self.totals:SetText("|cffff5959Enter a price and a quantity up to " .. row.item.postable .. ".|r")
    self.post:Disable()
    return
  end
  local _, neutral = self.app:market()
  local deposit = ns.Poster.deposit(row.item, self.duration, qty)
  self.totals:SetText(("Total %s, you get %s after the cut. Deposit %s (refunded if it sells)."):format(
    Money.short(price * qty), Money.short(ns.Fees.net(price * qty, neutral)), Money.short(deposit)))
  if ns.Poster.ready() then self.post:Enable() else self.post:Disable() end
end

function SellView:Post()
  local row = self.selected
  if not row then return end
  local price, qty = self:Values()
  if not (price and price > 0 and qty and qty > 0 and qty <= row.item.postable) then return end
  local ok, reason = ns.Poster.post(row.item, price, qty, self.duration)
  if not ok then
    ns.Api.print(reason)
    return
  end
  ns.Api.print(("Posted %d x %s at %s each."):format(qty, ns.ItemInfo.name(row.item.itemID) or "item",
    Money.short(price)))
  -- move straight on to the next item in the list
  local nextRow
  for i, r in ipairs(self.rows) do
    if r == row then nextRow = self.rows[i + 1] end
  end
  self.selected = nil
  self.detail:Hide()
  self:Layout()
  if nextRow then self:Select(nextRow) end
end
