-- HomeScreen: explains the addon and shows what's worth doing right now.
--
-- Sections (top to bottom, all reflow with the window width):
--   Status         how fresh your prices are and what's been learned
--   Get started    a checklist that ticks itself off, hidden once complete
--   Best deals     top deals from your last scan
--   Best mobs      most valuable mobs you've farmed
--   This session   gold per hour
--   What it does   one line per feature
local _, ns = ...

local HomeScreen = {}
HomeScreen.__index = HomeScreen
ns.HomeScreen = HomeScreen

local W, Money, Home = ns.Widgets, ns.Money, ns.HomeModel
local C = ns.Widgets.COLORS
local PAD = 14

function HomeScreen.new(app)
  local self = setmetatable({ app = app, pool = {}, used = 0 }, HomeScreen)
  app.db.ui.home = app.db.ui.home or {}
  return self
end

function HomeScreen:Build()
  local f = W.window({
    name = "CoinwiseHome", title = "Coinwise", width = 420, height = 520,
    minW = 300, minH = 260, store = self.app.db.ui.home,
  })
  self.frame = f

  local tagline = W.text(f, "GameFontHighlightSmall", C.muted)
  tagline:SetPoint("TOPLEFT", 12, -32)
  tagline:SetPoint("RIGHT", -12, 0)
  tagline:SetText(Home.TAGLINE)

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 4, -50)
  scroll:SetPoint("BOTTOMRIGHT", -26, 20)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  self.scroll, self.content = scroll, content

  f:SetScript("OnSizeChanged", function() self:Render() end)
  f:SetScript("OnShow", function() self:Render() end)
  f:Hide()
  return f
end

function HomeScreen:Toggle()
  if not self.frame then self:Build() end
  if self.frame:IsShown() then self.frame:Hide() else self.frame:Show() end
end

-- A tiny pool of font strings so re-rendering never leaks frames.
function HomeScreen:Line(template, color)
  self.used = self.used + 1
  local fs = self.pool[self.used]
  if not fs then
    fs = W.text(self.content, template)
    fs:SetWordWrap(true)
    self.pool[self.used] = fs
  end
  fs:SetFontObject(template or "GameFontHighlightSmall")
  local c = color or C.text
  fs:SetTextColor(c[1], c[2], c[3])
  fs:Show()
  return fs
end

function HomeScreen:Render()
  if not self.frame or not self.frame:IsShown() then return end
  local width = math.max(200, self.scroll:GetWidth() - PAD)
  self.content:SetWidth(width)
  self.used = 0
  local y = 0

  local function add(text, template, color, gap)
    local fs = self:Line(template, color)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD, -y)
    fs:SetWidth(width - PAD)
    fs:SetText(text)
    y = y + (fs.GetStringHeight and fs:GetStringHeight() or 14) + (gap or 4)
  end
  local function heading(text) y = y + 8; add(text, "GameFontNormal", C.gold, 6) end

  local app = self.app
  local state = app:homeState()
  local _, _, label = app:market()

  heading("Status")
  add(label .. ": " .. Home.scanStatus(state.lastScan, app.clock()))
  add(("%d mobs learned, %d recipes recorded"):format(state.mobsLearned, state.recipesKnown), nil, C.muted)

  local steps = Home.checklist(state)
  local allDone = true
  for _, s in ipairs(steps) do if not s.done then allDone = false end end
  if not allDone then
    heading("Get started")
    for _, s in ipairs(steps) do
      add((s.done and "|cff59e666done|r  " or "|cff8c8c99todo|r  ") .. s.text, nil, s.done and C.muted or C.text)
    end
  end

  local deals = app.db.lastDeals or {}
  if #deals > 0 then
    heading("Best deals from your last scan")
    for _, d in ipairs(deals) do
      local name = d.name or ns.ItemInfo.name(d.itemID) or "?"
      add(("%s  |cffffd100+%s|r  %s"):format(name, Money.short(d.profit), ns.PanelModel.LABELS[d.kind] or d.kind))
    end
  end

  local mobs = app:topMobs(5)
  if #mobs > 0 then
    heading("Best mobs to farm")
    for _, m in ipairs(mobs) do
      add(("%s  |cffffd100%s|r per kill  (%d kills)"):format(m.name or ("NPC " .. m.npcID), Money.short(m.ev), m.kills))
    end
  end

  local session = app.session:summary(GetMoney and GetMoney() or 0)
  if session.total ~= 0 then
    heading("This session")
    add(("%s gained (%s coin, %s loot), about |cffffd100%s|r per hour"):format(
      Money.short(session.total), Money.short(session.money), Money.short(session.loot), Money.short(session.perHour)))
  end

  heading("What it does")
  for _, feature in ipairs(Home.features()) do
    add(feature.title, "GameFontHighlight", C.text, 1)
    add(feature.text, nil, C.muted, 6)
  end
  add("Type /cw help for commands.", nil, C.muted)

  for i = self.used + 1, #self.pool do self.pool[i]:Hide() end
  self.content:SetHeight(y + PAD)
end
