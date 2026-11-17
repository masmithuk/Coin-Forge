-- SellView: the Sell tab of the auction panel.
--
--   ┌ list: everything in your bags you can auction, most valuable first ┐
--   │ Item              Qty   Price each   Total    Advice              │
--   └────────────────────────────────────────────────────────────────────┘
--   ┌ detail (shown once you pick a row) ─────────────────────────────────┐
--   │ [icon] Item name x20                                   [  Post  ]  │
--   │ Why this price (bait ignored, price war, undercut...)               │
--   │ Price each [ 1g 2s 3c ]  Qty [ 20 ] / 20   2 h | 8 h | 24 h         │
--   │ Total ... / or, if Post is off, exactly why                         │
--   │ Live prices: normal 1g 5s, floor 63s                                │
--   │   Price each   Qty   What we made of it                             │
--   │   20s           2    bait, ignored                                  │
--   │   1g 2s 3c     20    your price                                     │
--   │   1g 2s 4c     35    cheapest real listing: undercut by 1c          │
--   └─────────────────────────────────────────────────────────────────────┘
--
-- Picking a row fills in the suggestion from the last scan straight away, then
-- a live search refines it. Every field stays editable. Post (or Enter in a
-- field) creates the auction and moves on to the next item. The Post button is
-- never off without a visible reason.
local _, ns = ...

local SellView = {}
SellView.__index = SellView
ns.SellView = SellView

local W, Money = ns.Widgets, ns.Money
local C = ns.Widgets.COLORS
local AMBER = { 1, 0.65, 0.2 }

local COLUMNS = {
  { key = "name", title = "Item", min = 110, weight = 4, priority = 1 },
  { key = "qty", title = "Qty", min = 34, weight = 0, priority = 3, justify = "RIGHT" },
  { key = "price", title = "Price each", min = 70, weight = 1, priority = 1, justify = "RIGHT" },
  { key = "total", title = "Total", min = 70, weight = 1, priority = 2, justify = "RIGHT" },
  { key = "advice", title = "Advice", min = 70, weight = 1, priority = 4 },
}

local PRICE_COLUMNS = {
  { key = "price", title = "Price each", min = 70, weight = 1, priority = 1, justify = "RIGHT" },
  { key = "qty", title = "Qty", min = 34, weight = 0, priority = 1, justify = "RIGHT" },
  { key = "note", title = "What we made of it", min = 120, weight = 3, priority = 2 },
}

local ADVICE = {
  post = { "Post", C.good },
  vendor = { "Vendor it", C.gold },
  disenchant = { "Disenchant", { 0.75, 0.55, 1 } },
  refine = { "Craft first", { 0.4, 0.8, 1 } },
  manual = { "Set a price", C.muted },
}

local STATUS = {
  bait = { "bait, ignored", C.bad },
  war = { "price war, ignored", C.bad },
  yours = { "your auction", C.good },
  above = { "", C.text },
  new = { "your price", C.gold },
}

-- Detail pane height: roomy when the window is tall, compact when it's short.
local DETAIL_MIN, DETAIL_MAX = 170, 300
local RECHECK_LIMIT = 30

--- Why Post can or can't be pressed. Pure, so it can be reasoned about alone.
--- @return enabled, message, color
function SellView.postState(price, qty, maxQty, ready)
  if not price or price <= 0 then
    return false, "Post is off: type a price, for example 1g 20s or 85s.", C.bad
  end
  if not qty or qty <= 0 or qty > maxQty then
    return false, ("Post is off: quantity must be between 1 and %d."):format(maxQty), C.bad
  end
  if not ready then
    return false, "Post is off for a moment: the auction house is busy (it limits how fast addons can send "
      .. "requests). It turns back on by itself.", AMBER
  end
  return true
end

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
  self.parent = parent
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
  d:SetHeight(DETAIL_MIN)
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
  -- explain a disabled button on hover too, not just in the status line
  if self.post.SetMotionScriptsWhileDisabled then self.post:SetMotionScriptsWhileDisabled(true) end
  self.post:SetScript("OnEnter", function(b)
    if b:IsEnabled() or not self.blockReason then return end
    GameTooltip:SetOwner(b, "ANCHOR_TOP")
    GameTooltip:SetText(self.blockReason, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  self.post:SetScript("OnLeave", function() GameTooltip:Hide() end)

  self.reason = W.text(d, "GameFontHighlightSmall", C.muted)
  self.reason:SetPoint("TOPLEFT", self.icon, "BOTTOMLEFT", 0, -4)
  self.reason:SetPoint("RIGHT", -8, 0)
  self.reason:SetWordWrap(true)
  self.reason:SetHeight(26)

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

  self.status = W.text(d, "GameFontHighlightSmall")
  self.status:SetPoint("TOPLEFT", priceLabel, "BOTTOMLEFT", 0, -10)
  self.status:SetPoint("RIGHT", -8, 0)
  self.status:SetWordWrap(true)

  self.marketLine = W.text(d, "GameFontHighlightSmall", C.muted)
  self.marketLine:SetPoint("TOPLEFT", self.status, "BOTTOMLEFT", 0, -6)
  self.marketLine:SetPoint("RIGHT", -8, 0)
  self.marketLine:SetWordWrap(false)

  self.prices = W.list(d, {
    columns = PRICE_COLUMNS,
    rowHeight = 16,
    cells = function(l)
      return { price = Money.short(l.price), qty = tostring(l.count), note = l.note }
    end,
    color = function(l)
      local c = STATUS[l.status] and STATUS[l.status][2] or C.text
      return { note = c, price = l.status == "new" and C.gold or nil }
    end,
    emptyText = function() return "Nobody else is selling this right now." end,
  })
  self.prices:SetPoint("TOPLEFT", self.marketLine, "BOTTOMLEFT", -4, -4)
  self.prices:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -4, 4)

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
  local height = math.max(DETAIL_MIN, math.min(DETAIL_MAX, math.floor((bottom:GetHeight() or 400) * 0.55)))
  self.detail:SetHeight(height)
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
  self.suggestion, self.live = s, live
  self.price:SetText(s.price and Money.format(s.price) or "")
  local source = live and "" or "From your last scan, checking live prices... "
  self.reason:SetText(source .. (s.reason or ""))
  self:UpdateTotals()
end

function SellView:Values()
  return Money.parse(self.price:GetText()), tonumber(self.qty:GetText())
end

--- The price list shown under the inputs: every listing with what the
--- pricing made of it, plus a "your price" row where your auction would sit.
function SellView:PriceRows(yourPrice, qty)
  local s = self.suggestion
  local rows = {}
  for _, l in ipairs(s and s.listings or {}) do
    local note = STATUS[l.status] and STATUS[l.status][1] or ""
    if l.status == "undercut" then
      note = "cheapest real listing: undercut by " .. Money.short(self.app.settings.undercut)
    end
    rows[#rows + 1] = { price = l.price, count = l.count, status = l.status, note = note }
  end
  if yourPrice then
    local mine = { price = yourPrice, count = qty or 0, status = "new", note = STATUS.new[1] }
    local at = #rows + 1
    for i, r in ipairs(rows) do
      if r.price >= yourPrice and r.status ~= "bait" and r.status ~= "war" then at = i break end
    end
    table.insert(rows, at, mine)
  end
  return rows
end

function SellView:UpdateTotals()
  local row = self.selected
  if not row then return end
  local price, qty = self:Values()
  local ready = ns.Poster.ready()
  local enabled, message, color = SellView.postState(price, qty, row.item.postable, ready)

  local s = self.suggestion
  if s and s.reference then
    self.marketLine:SetText(("%s: normal price %s, floor %s (we won't follow prices below this)."):format(
      self.live and "Live prices" or "Last scan", Money.short(s.reference), Money.short(s.floor or 0)))
  else
    self.marketLine:SetText(self.live and "Live prices" or "Last scan")
  end
  self.prices:SetItems(self:PriceRows(price, qty))

  if enabled then
    local _, neutral = self.app:market()
    local deposit = ns.Poster.deposit(row.item, self.duration, qty)
    self.status:SetText(("Total %s, you get %s after the cut. Deposit %s (refunded if it sells)."):format(
      Money.short(price * qty), Money.short(ns.Fees.net(price * qty, neutral)), Money.short(deposit)))
    self.status:SetTextColor(C.text[1], C.text[2], C.text[3])
    self.blockReason = nil
    self.rechecks = 0
    self.post:Enable()
  else
    self.status:SetText(message)
    self.status:SetTextColor(color[1], color[2], color[3])
    self.blockReason = message
    self.post:Disable()
    -- only "busy" clears by itself: re-check shortly in case the ready event is
    -- missed, for up to RECHECK_LIMIT seconds
    self.rechecks = ready and 0 or (self.rechecks or 0)
    if not ready and not self.recheck and self.rechecks < RECHECK_LIMIT and C_Timer then
      self.recheck = true
      self.rechecks = self.rechecks + 1
      C_Timer.After(1, function()
        self.recheck = false
        self:UpdateTotals()
      end)
    end
  end
end

--- The auction house can take requests again (AUCTION_HOUSE_THROTTLED_SYSTEM_READY).
function SellView:OnAuctionHouseReady()
  if self.selected then self:UpdateTotals() end
end

function SellView:Post()
  local row = self.selected
  if not row then return end
  local price, qty = self:Values()
  if not SellView.postState(price, qty, row.item.postable, ns.Poster.ready()) then return end
  local ok, reason = ns.Poster.post(row.item, price, qty, self.duration)
  if not ok then
    self.status:SetText(reason)
    self.status:SetTextColor(C.bad[1], C.bad[2], C.bad[3])
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
