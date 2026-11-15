-- AuctionPanel: the ForeverGold panel docked to the right of the auction house.
--
-- Two views, Deals and Crafting, chosen with text tabs. The only button is
-- Scan. Clicking any row searches for that item in Blizzard's Buy tab right
-- next to it, so buying always goes through the normal, safe Blizzard UI.
local _, ns = ...

local AuctionPanel = {}
AuctionPanel.__index = AuctionPanel
ns.AuctionPanel = AuctionPanel

local W, Money, PM = ns.Widgets, ns.Money, ns.PanelModel
local C = ns.Widgets.COLORS

local DEAL_COLUMNS = {
  { key = "name", title = "Item", min = 110, weight = 4, priority = 1 },
  { key = "kind", title = "Type", min = 58, weight = 0, priority = 3 },
  { key = "price", title = "Buy up to", min = 64, weight = 1, priority = 2, justify = "RIGHT" },
  { key = "qty", title = "Qty", min = 34, weight = 0, priority = 4, justify = "RIGHT" },
  { key = "profit", title = "Profit", min = 64, weight = 1, priority = 1, justify = "RIGHT" },
  { key = "note", title = "How", min = 120, weight = 3, priority = 5 },
}

local CRAFT_COLUMNS = {
  { key = "name", title = "Recipe", min = 110, weight = 4, priority = 1 },
  { key = "cost", title = "Cost", min = 60, weight = 1, priority = 2, justify = "RIGHT" },
  { key = "revenue", title = "Sells for", min = 60, weight = 1, priority = 3, justify = "RIGHT" },
  { key = "profit", title = "Profit", min = 64, weight = 1, priority = 1, justify = "RIGHT" },
  { key = "crafter", title = "Who", min = 90, weight = 2, priority = 4 },
}

local CRAFT_HELP = "Profit or loss of every recipe your characters know, at today's market prices."

--- Searches the item in the Blizzard Buy tab. Returns false if the AH UI changed.
function AuctionPanel.search(name)
  local ah = AuctionHouseFrame
  if not (name and ah and ah.SearchBar) then return false end
  if ah.SetDisplayMode and _G.AuctionHouseFrameDisplayMode then
    pcall(ah.SetDisplayMode, ah, _G.AuctionHouseFrameDisplayMode.Buy)
  end
  local bar = ah.SearchBar
  if bar.SearchBox then bar.SearchBox:SetText(name) end
  if bar.StartSearch then pcall(bar.StartSearch, bar) end
  return true
end

local function itemName(itemID)
  return ns.ItemInfo.name(itemID)
end

function AuctionPanel.new(app)
  local self = setmetatable({ app = app, view = "deals", kind = "all", profession = "all" }, AuctionPanel)
  self.store = app.db.ui.auctionPanel or {}
  app.db.ui.auctionPanel = self.store
  self.onlyCanDo = self.store.onlyCanDo == true
  app.events:on("scanStarted", function() self:UpdateStatus() end)
  app.events:on("scanProgress", function(done, total) self:UpdateStatus(done, total) end)
  app.events:on("opportunitiesUpdated", function() self:Refresh() end)
  app.events:on("recipesUpdated", function() if self.view == "crafting" then self:Refresh() end end)
  return self
end

function AuctionPanel:Build(anchor)
  local f = CreateFrame("Frame", "ForeverGoldAuctionPanel", anchor or UIParent, "BackdropTemplate")
  self.frame = f
  f:SetSize(self.store.width or 440, self.store.height or (anchor and anchor:GetHeight() or 440))
  if anchor then f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0) else f:SetPoint("CENTER") end
  f:SetClampedToScreen(true)
  W.skin(f)
  W.makeResizable(f, 300, 260, 1000, 900)
  f.saveGeometry = function()
    self.store.width, self.store.height = f:GetWidth(), f:GetHeight()
  end

  -- Header: title, where you are, and how fresh the data is.
  local title = W.text(f, "GameFontNormalLarge", C.gold)
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("ForeverGold")
  self.marketText = W.text(f, "GameFontHighlightSmall", C.muted)
  self.marketText:SetPoint("LEFT", title, "RIGHT", 8, -1)

  self.status = W.text(f, "GameFontHighlightSmall", C.muted)
  self.status:SetPoint("TOPLEFT", 12, -32)
  self.status:SetPoint("RIGHT", -110, 0)
  self.status:SetWordWrap(false)

  -- The one button: Scan. It shows its own cooldown instead of an error.
  self.scanButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  self.scanButton:SetSize(96, 22)
  self.scanButton:SetPoint("TOPRIGHT", -10, -10)
  self.scanButton:SetScript("OnClick", function() self:Scan() end)
  self.scanButton:SetScript("OnEnter", function(b)
    GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Scan the whole auction house", 1, 1, 1)
    GameTooltip:AddLine("Takes a few seconds. The server allows one full scan every 15 minutes.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  self.scanButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- View tabs
  self.viewTabs = W.tabBar(f, function(view) self:SetView(view) end)
  self.viewTabs:SetPoint("TOPLEFT", 8, -50)
  self.viewTabs:SetPoint("RIGHT", -8, 0)

  -- Filter row: kind / profession tabs plus one toggle.
  self.filterTabs = W.tabBar(f, function(kind) self:SetFilter(kind) end)
  self.filterTabs:SetPoint("TOPLEFT", self.viewTabs, "BOTTOMLEFT", 0, -2)
  self.filterTabs:SetPoint("RIGHT", -150, 0)

  self.canDo = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  self.canDo:SetSize(20, 20)
  self.canDo:SetPoint("TOPRIGHT", self.viewTabs, "BOTTOMRIGHT", -110, -2)
  self.canDo:SetChecked(self.onlyCanDo)
  local canDoLabel = W.text(f, "GameFontHighlightSmall")
  canDoLabel:SetPoint("LEFT", self.canDo, "RIGHT", 2, 0)
  canDoLabel:SetText("Only what I can do")
  self.canDo:SetScript("OnClick", function(b)
    self.onlyCanDo = b:GetChecked() and true or false
    self.store.onlyCanDo = self.onlyCanDo
    self:Refresh()
  end)

  self.deals = W.list(f, {
    columns = DEAL_COLUMNS,
    cells = function(o)
      local row = PM.row(o, itemName)
      return { name = row.name, kind = row.kindLabel, price = row.price, qty = row.qty,
        profit = row.profit, note = row.note }
    end,
    color = function(o) if not o.canDo then return { name = C.muted, note = C.muted } end end,
    onClick = function(o) AuctionPanel.search(itemName(o.itemID) or o.name) end,
    onEnter = function(row, o) self:DealTooltip(row, o) end,
    emptyText = function() return self:EmptyText() end,
  })

  self.crafts = W.list(f, {
    columns = CRAFT_COLUMNS,
    cells = function(r) return self:CraftCells(r) end,
    color = function(r)
      if r.profit then return { profit = r.profit >= 0 and C.good or C.bad } end
      return { profit = C.muted }
    end,
    onClick = function(r) AuctionPanel.search(itemName(r.recipe.outputItemID) or r.recipe.name) end,
    onEnter = function(row, r) self:CraftTooltip(row, r) end,
    emptyText = function()
      return "No recipes recorded yet.\nOpen each profession window once (on any character) and they'll appear here."
    end,
  })

  self.footer = W.text(f, "GameFontHighlightSmall", C.muted)
  self.footer:SetPoint("BOTTOMLEFT", 12, 8)
  self.footer:SetPoint("RIGHT", -24, 0)
  self.footer:SetWordWrap(false)

  f:SetScript("OnSizeChanged", function() self:LayoutLists() end)
  f:SetScript("OnShow", function() self:Refresh() end)
  f:SetScript("OnHide", function() if self.ticker then self.ticker:Cancel() self.ticker = nil end end)
  self:LayoutLists()
  return f
end

function AuctionPanel:LayoutLists()
  for _, list in ipairs({ self.deals, self.crafts }) do
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", self.filterTabs, "BOTTOMLEFT", 0, -4)
    list:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -8, 26)
  end
end

function AuctionPanel:Show(anchor)
  if not self.frame then self:Build(anchor) end
  self.frame:Show()
  self:Refresh()
end

function AuctionPanel:Hide()
  if self.frame then self.frame:Hide() end
end

-- Actions ------------------------------------------------------------------------

function AuctionPanel:Scan()
  local ok, reason = self.app:startScan()
  if not ok and reason == "unsupported" then
    ns.Api.print("This client doesn't support full auction house scans.")
  end
  self:UpdateStatus()
end

function AuctionPanel:SetView(view)
  self.view = view
  self:Refresh()
end

function AuctionPanel:SetFilter(kind)
  if self.view == "deals" then self.kind = kind else self.profession = kind end
  self:Refresh()
end

-- Rendering ------------------------------------------------------------------------

function AuctionPanel:UpdateStatus(done, total)
  if not self.frame then return end
  local app = self.app
  local key, _, label = app:market()
  self.marketText:SetText(label)

  if app.scanner.running then
    if done and total then
      self.status:SetText(("Scanning... %d / %d auctions"):format(done, total))
    else
      self.status:SetText("Scanning... waiting for the server")
    end
  else
    local text = ns.HomeModel.scanStatus(app.prices:lastScan(key), app.clock())
    local result = app.scanner.lastResult
    if result and result.marketKey == key then text = text .. (" - %d items priced"):format(result.itemCount) end
    self.status:SetText(text)
  end

  local wait = app.scanner:cooldownLeft()
  local busy = app.scanner.running
  if busy then
    self.scanButton:SetText("Scanning")
  elseif wait > 0 then
    self.scanButton:SetText(("Scan in %d:%02d"):format(math.floor(wait / 60), wait % 60))
  else
    self.scanButton:SetText("Scan")
  end
  if busy or wait > 0 then self.scanButton:Disable() else self.scanButton:Enable() end

  -- tick the countdown only while it's visible and counting
  if (busy or wait > 0) and not self.ticker and C_Timer and C_Timer.NewTicker then
    self.ticker = C_Timer.NewTicker(1, function()
      self:UpdateStatus()
      if not app.scanner.running and app.scanner:cooldownLeft() == 0 and self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
      end
    end)
  end
end

function AuctionPanel:EmptyText()
  local app = self.app
  local result = app.scanner.lastResult
  if app.scanner.running then return "Scanning..." end
  if not result or result.marketKey ~= (app:market()) then
    return "Press Scan to find deals on this auction house.\n\n"
      .. "Your saved prices already power tooltips, crafting and mob values."
  end
  if self.onlyCanDo then return "Nothing you can do right now. Untick \"Only what I can do\" to see everything." end
  return "No deals in this scan.\n\nMost deals need " .. app.settings.minHistoryDays
    .. " days of price history, so they show up once you've scanned on a few different days."
end

function AuctionPanel:Refresh()
  if not self.frame or not self.frame:IsShown() then return end
  self:UpdateStatus()
  self.viewTabs:SetTabs({
    { kind = "deals", label = "Deals", help = "Ways to profit from what's listed right now." },
    { kind = "crafting", label = "Crafting", help = CRAFT_HELP },
  }, self.view)

  if self.view == "deals" then
    self.crafts:Hide()
    self.deals:Show()
    local all = PM.filter(self.app.lastOpportunities, { kind = "all", onlyCanDo = self.onlyCanDo })
    local tabs = PM.tabs(all)
    for _, t in ipairs(tabs) do t.help = PM.HELP[t.kind] end
    local valid = false
    for _, t in ipairs(tabs) do if t.kind == self.kind then valid = true end end
    if not valid then self.kind = "all" end
    self.filterTabs:SetTabs(tabs, self.kind)
    local shown = PM.filter(all, { kind = self.kind })
    self.deals:SetItems(shown)
    local s = PM.summary(shown)
    self.footer:SetText(s.count > 0
      and ("%d deals, about %s profit in total. Click a row to find it."):format(s.count, Money.short(s.profit))
      or "")
  else
    self.deals:Hide()
    self.crafts:Show()
    self:RefreshCrafts()
  end
  self:LayoutLists()
end

function AuctionPanel:RefreshCrafts()
  local rows = self.app:craftRows()
  local professions, counts, filtered = {}, {}, {}
  for _, r in ipairs(rows) do
    if not self.onlyCanDo or r.recipe.knownByPlayer then
      local p = r.recipe.profession or "?"
      if not counts[p] then professions[#professions + 1] = p end
      counts[p] = (counts[p] or 0) + 1
      if self.profession == "all" or self.profession == p then filtered[#filtered + 1] = r end
    end
  end
  table.sort(professions)
  local tabs = { { kind = "all", label = "All", count = tostring(#rows) } }
  for _, p in ipairs(professions) do tabs[#tabs + 1] = { kind = p, label = p, count = tostring(counts[p]) } end
  if self.profession ~= "all" and not counts[self.profession] then self.profession = "all" end
  self.filterTabs:SetTabs(tabs, self.profession)
  self.crafts:SetItems(filtered)

  local profitable = 0
  for _, r in ipairs(filtered) do if r.profit and r.profit > 0 then profitable = profitable + 1 end end
  self.footer:SetText(#filtered > 0 and ("%d of %d recipes make a profit."):format(profitable, #filtered) or "")
end

function AuctionPanel:CraftCells(r)
  local recipe = r.recipe
  local crafter = recipe.knownByPlayer and "You" or table.concat(recipe.crafters or {}, ", ")
  return {
    name = recipe.name,
    cost = r.cost and Money.short(r.cost) or "?",
    revenue = r.revenue and Money.short(r.revenue) or "?",
    profit = r.profit and Money.short(r.profit) or (#r.missing > 0 and "needs prices" or "?"),
    crafter = crafter,
  }
end

function AuctionPanel:DealTooltip(row, o)
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  if GameTooltip.SetItemByID then GameTooltip:SetItemByID(o.itemID) end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(PM.LABELS[o.kind] .. ": " .. (PM.HELP[o.kind] or ""), C.gold[1], C.gold[2], C.gold[3], true)
  if o.qty then
    local buy = o.qty .. (o.maxPrice and (" at up to " .. Money.short(o.maxPrice)) or "")
    GameTooltip:AddDoubleLine("Buy", buy, 0.8, 0.8, 0.8, 1, 1, 1)
  end
  GameTooltip:AddDoubleLine("Cost", Money.short(o.cost), 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddDoubleLine("You get back", Money.short(o.revenue), 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddDoubleLine("Profit", Money.short(o.profit), 0.8, 0.8, 0.8, C.gold[1], C.gold[2], C.gold[3])
  if o.note then GameTooltip:AddLine(o.note, 1, 1, 1, true) end
  GameTooltip:AddLine("Click to search for it", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end

function AuctionPanel:CraftTooltip(row, r)
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  if GameTooltip.SetItemByID then GameTooltip:SetItemByID(r.recipe.outputItemID) end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Reagents", C.gold[1], C.gold[2], C.gold[3])
  for _, reagent in ipairs(r.recipe.reagents) do
    local value = self.app:value(reagent.itemID) or self.app.db.vendorPrices[reagent.itemID]
    GameTooltip:AddDoubleLine(reagent.qty .. " x " .. (itemName(reagent.itemID) or "?"),
      value and Money.short(value * reagent.qty) or "no price", 0.8, 0.8, 0.8, 1, 1, 1)
  end
  if #r.missing > 0 then
    GameTooltip:AddLine("Scan the AH or visit a vendor that sells the missing reagents.", 0.8, 0.8, 0.8, true)
  end
  GameTooltip:Show()
end
