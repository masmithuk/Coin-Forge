-- AuctionPanel: the Coin Forge panel docked to the right of the auction house.
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

local CONVERSION_COLUMNS = {
  { key = "name", title = "Conversion", min = 140, weight = 4, priority = 1 },
  { key = "cost", title = "Buy for", min = 60, weight = 1, priority = 2, justify = "RIGHT" },
  { key = "revenue", title = "Sells for", min = 60, weight = 1, priority = 3, justify = "RIGHT" },
  { key = "profit", title = "Profit", min = 64, weight = 1, priority = 1, justify = "RIGHT" },
}

local CONVERSION_HELP = "Every essence combine and split, profitable or not. No profession needed."

local CRAFT_HELP ="Profit or loss of every recipe your characters know, at today's market prices."

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
  local self = setmetatable(
    { app = app, view = "deals", kind = "all", profession = "all", convFilter = "all" }, AuctionPanel)
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
  local f = CreateFrame("Frame", "CoinForgeAuctionPanel", anchor or UIParent, "BackdropTemplate")
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
  title:SetText("Coin Forge")
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
  self.canDoLabel = W.text(f, "GameFontHighlightSmall")
  self.canDoLabel:SetPoint("LEFT", self.canDo, "RIGHT", 2, 0)
  self.canDoLabel:SetText("Only what I can do")
  self.showUnlearned = self.store.showUnlearned == true
  self.unlearned = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  self.unlearned:SetSize(20, 20)
  self.unlearned:SetPoint("RIGHT", self.canDo, "LEFT", -96, 0)
  self.unlearned:SetChecked(self.showUnlearned)
  self.unlearnedLabel = W.text(f, "GameFontHighlightSmall")
  self.unlearnedLabel:SetPoint("LEFT", self.unlearned, "RIGHT", 2, 0)
  self.unlearnedLabel:SetText("Show unlearned")
  self.unlearned:SetScript("OnEnter", function(b)
    GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Show unlearned recipes", 1, 1, 1)
    GameTooltip:AddLine("Also list recipes none of your characters have learned yet, usually ones above "
      .. "your skill, with their profit, so you can see what's worth learning.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  self.unlearned:SetScript("OnLeave", function() GameTooltip:Hide() end)
  self.unlearned:SetScript("OnClick", function(b)
    self.showUnlearned = b:GetChecked() and true or false
    self.store.showUnlearned = self.showUnlearned
    self:Refresh()
  end)

  self.canDo:SetScript("OnEnter", function(b)
    GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Only what I can do", 1, 1, 1)
    GameTooltip:AddLine("Hides disenchanting your Enchanting skill is too low for, and crafts this character "
      .. "doesn't know. Flips, vendor snipes, conversions and other-AH deals are open to everyone, "
      .. "so they always stay.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  self.canDo:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
      local c = { profit = r.profit and (r.profit >= 0 and C.good or C.bad) or C.muted }
      if r.recipe.learnedBySomeone == false then c.name, c.crafter = C.muted, C.muted end
      return c
    end,
    onClick = function(r) AuctionPanel.search(itemName(r.recipe.outputItemID) or r.recipe.name) end,
    onEnter = function(row, r) self:CraftTooltip(row, r) end,
    emptyText = function()
      return "No recipes recorded yet.\nOpen each profession window once (on any character) and they'll appear here."
    end,
  })

  self.convs = W.list(f, {
    columns = CONVERSION_COLUMNS,
    cells = function(r)
      return {
        name = r.conversion.name,
        cost = r.cost and Money.short(r.cost) or "?",
        revenue = r.revenue and Money.short(r.revenue) or "?",
        profit = r.profit and Money.short(r.profit) or "needs prices",
      }
    end,
    color = function(r)
      if r.profit then return { profit = r.profit > 0 and C.good or C.bad } end
      return { profit = C.muted }
    end,
    onClick = function(r) AuctionPanel.search(itemName(r.conversion.inputs[1][1])) end,
    onEnter = function(row, r) self:ConversionTooltip(row, r) end,
    emptyText = function() return "No conversions defined." end,
  })

  self.sell = ns.SellView.new(self.app, f)

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
  if self.sell then self.sell:SetArea(self.filterTabs, self.frame) end
  for _, list in ipairs({ self.deals, self.crafts, self.convs }) do
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

--- Bags changed (an item was posted, looted or moved): refresh the Sell list.
function AuctionPanel:OnBagsChanged()
  if self.frame and self.frame:IsShown() and self.view == "sell" then self.sell:Refresh() end
end

--- The auction house can take requests again: re-enable Post if it was waiting.
function AuctionPanel:OnAuctionHouseReady()
  if self.sell then self.sell:OnAuctionHouseReady() end
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
  if self.view == "deals" then self.kind = kind
  elseif self.view == "crafting" then self.profession = kind
  else self.convFilter = kind end
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

  local wait = app.scanner:cooldownLeft(key)
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
      if not app.scanner.running and app.scanner:cooldownLeft((app:market())) == 0 and self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
      end
    end)
  end
end

function AuctionPanel:EmptyText()
  local app = self.app
  local result = app.scanner.lastResult
  return PM.emptyText({
    running = app.scanner.running,
    hasResult = result ~= nil and result.marketKey == (app:market()),
    cooldown = app.scanner:cooldownLeft((app:market())),
    onlyCanDo = self.onlyCanDo,
    minHistoryDays = app.settings.minHistoryDays,
  })
end

function AuctionPanel:Refresh()
  if not self.frame or not self.frame:IsShown() then return end
  self:UpdateStatus()
  self.viewTabs:SetTabs({
    { kind = "deals", label = "Deals", help = "Ways to profit from what's listed right now." },
    { kind = "crafting", label = "Crafting", help = CRAFT_HELP },
    { kind = "sell", label = "Sell", help = "Everything in your bags, priced to sell. Pick one, check it, Post." },
    { kind = "conversions", label = "Conversions", help = CONVERSION_HELP },
  }, self.view)

  self.deals:SetShown(self.view == "deals")
  self.crafts:SetShown(self.view == "crafting")
  self.convs:SetShown(self.view == "conversions")
  self.sell:SetShown(self.view == "sell")
  local filterable = self.view == "deals" or self.view == "crafting"
  self.canDo:SetShown(filterable) -- everyone can convert and sell
  self.canDoLabel:SetShown(filterable)
  local crafting = self.view == "crafting"
  self.unlearned:SetShown(crafting)
  self.unlearnedLabel:SetShown(crafting)
  -- leave room on the filter row for whichever toggles are showing
  self.filterTabs:SetPoint("RIGHT", self.frame, "RIGHT", crafting and -270 or (filterable and -150 or -8), 0)

  if self.view == "deals" then
    local all = PM.filter(self.app.lastOpportunities, { kind = "all", onlyCanDo = self.onlyCanDo })
    local tabs = PM.tabs(all)
    for _, t in ipairs(tabs) do t.help = PM.HELP[t.kind] end
    local valid = false
    for _, t in ipairs(tabs) do if t.kind == self.kind then valid = true end end
    if not valid then self.kind = "all" end
    self.filterTabs:SetTabs(tabs, self.kind)
    local shown = PM.filter(all, { kind = self.kind })
    self.deals:SetItems(shown)
    self.footer:SetText(PM.footer(self.app.lastOpportunities, { kind = self.kind, onlyCanDo = self.onlyCanDo }))
  elseif self.view == "crafting" then
    self:RefreshCrafts()
  elseif self.view == "sell" then
    self.filterTabs:SetTabs({}, nil)
    self.footer:SetText("Prices skip bait and price wars. Gear is buyout-only, so nobody wins it with a low bid.")
  else
    self:RefreshConversions()
  end
  self:LayoutLists()
end

function AuctionPanel:RefreshConversions()
  local rows = self.app:conversionRows()
  local filtered, profitable = {}, 0
  for _, r in ipairs(rows) do
    local direction = r.conversion.key:match("^(%a+):")
    if self.convFilter == "all" or self.convFilter == direction then
      filtered[#filtered + 1] = r
      if r.profit and r.profit > 0 then profitable = profitable + 1 end
    end
  end
  self.filterTabs:SetTabs({
    { kind = "all", label = "All", help = CONVERSION_HELP },
    { kind = "combine", label = "Combine", help = "Buy 3 lesser essences, right-click to make 1 greater." },
    { kind = "split", label = "Split", help = "Buy 1 greater essence, right-click to break it into 3 lesser." },
  }, self.convFilter)
  self.convs:SetItems(filtered)
  self.footer:SetText(("%d of %d profitable right now. Right-click the essence in your bags to convert it.")
    :format(profitable, #filtered))
end

function AuctionPanel:ConversionTooltip(row, r)
  local conv = r.conversion
  local input, inQty = conv.inputs[1][1], conv.inputs[1][2]
  local output, outQty = conv.outputs[1][1], conv.outputs[1][2]
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetText(conv.name, C.gold[1], C.gold[2], C.gold[3])
  GameTooltip:AddDoubleLine(("Buy %d x %s"):format(inQty, itemName(input) or "?"),
    r.cost and Money.short(r.cost) or "no price", 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddDoubleLine(("Sell %d x %s"):format(outQty, itemName(output) or "?"),
    r.revenue and Money.short(r.revenue) or "no price", 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddLine("Sell price is after the AH cut. No profession needed.", 0.6, 0.6, 0.6, true)
  GameTooltip:AddLine("Click to search for the essence to buy", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end

function AuctionPanel:RefreshCrafts()
  local rows = self.app:craftRows({ includeUnlearned = self.showUnlearned })
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

  local profitable, hidden, notLearned = 0, 0, 0
  for _, r in ipairs(filtered) do if r.profit and r.profit > 0 then profitable = profitable + 1 end end
  for _, r in ipairs(rows) do
    if r.recipe.learnedBySomeone == false then notLearned = notLearned + 1
    elseif not r.recipe.knownByPlayer then hidden = hidden + 1 end
  end
  local text = #filtered > 0 and ("%d of %d recipes make a profit."):format(profitable, #filtered) or ""
  if notLearned > 0 then text = text .. (" %d not learned yet."):format(notLearned) end
  if hidden == 0 and notLearned == 0 and #rows > 0 then
    text = text .. " (this character knows all of them)"
  elseif hidden > 0 and self.onlyCanDo then
    text = text .. (" %d known only by your other characters are hidden."):format(hidden)
  end
  self.footer:SetText(text)
end

function AuctionPanel:CraftCells(r)
  local recipe = r.recipe
  local crafter = recipe.knownByPlayer and "You"
    or (recipe.learnedBySomeone == false and "Not learned")
    or table.concat(recipe.crafters or {}, ", ")
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
  if r.recipe.learnedBySomeone == false then
    GameTooltip:AddLine("None of your characters have learned this yet.", 1, 0.65, 0.2, true)
  end
  GameTooltip:Show()
end
