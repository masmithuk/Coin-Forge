-- MerchantOverlay: makes vendor items worth more on the AH glow green and
-- shows the profit under them. A one-line summary appears under the merchant
-- window only when there's something worth buying, with no extra buttons.
local _, ns = ...

local MerchantOverlay = {}
MerchantOverlay.__index = MerchantOverlay
ns.MerchantOverlay = MerchantOverlay

local W, Money = ns.Widgets, ns.Money
local C = ns.Widgets.COLORS

function MerchantOverlay.new(app)
  return setmetatable({ app = app, marks = {} }, MerchantOverlay)
end

local function mark(self, i)
  local m = self.marks[i]
  if m then return m end
  local button = _G["MerchantItem" .. i .. "ItemButton"]
  if not button then return nil end
  m = {}
  m.glow = button:CreateTexture(nil, "OVERLAY")
  m.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  m.glow:SetBlendMode("ADD")
  m.glow:SetPoint("CENTER")
  m.glow:SetSize(button:GetWidth() * 1.8, button:GetHeight() * 1.8)
  m.label = W.text(button, "GameFontHighlightSmall", C.good)
  m.label:SetPoint("TOPLEFT", button, "BOTTOMLEFT", -2, -1)
  self.marks[i] = m
  return m
end

local function summary(self)
  if self.summary then return self.summary end
  local s = CreateFrame("Frame", nil, MerchantFrame, "BackdropTemplate")
  s:SetPoint("TOPLEFT", MerchantFrame, "BOTTOMLEFT", 0, -2)
  s:SetPoint("TOPRIGHT", MerchantFrame, "BOTTOMRIGHT", 0, -2)
  s:SetHeight(22)
  W.skin(s)
  s.text = W.text(s, "GameFontHighlightSmall")
  s.text:SetPoint("LEFT", 8, 0)
  s.text:SetPoint("RIGHT", -8, 0)
  s.text:SetWordWrap(false)
  self.summary = s
  return s
end

function MerchantOverlay:HideAll()
  for _, m in pairs(self.marks) do
    m.glow:Hide()
    m.label:Hide()
  end
  if self.summary then self.summary:Hide() end
end

function MerchantOverlay:Update()
  if not MerchantFrame or not MerchantFrame:IsShown() then return end
  local buybackTab = MerchantFrame.selectedTab and MerchantFrame.selectedTab ~= 1
  if not self.app.settings.showMerchant or buybackTab then return self:HideAll() end

  local deals = self.app:merchantDeals()
  local byIndex = {}
  for _, d in ipairs(deals) do byIndex[d.index] = d end

  local perPage = MERCHANT_ITEMS_PER_PAGE or 10
  local page = MerchantFrame.page or 1
  for i = 1, perPage do
    local m = mark(self, i)
    if m then
      local deal = byIndex[(page - 1) * perPage + i]
      if deal then
        local c = deal.strong and C.good or C.gold
        m.glow:SetVertexColor(c[1], c[2], c[3])
        m.label:SetText("+" .. Money.short(deal.profit) .. (deal.limited and " (limited)" or ""))
        m.label:SetTextColor(c[1], c[2], c[3])
        m.glow:Show()
        m.label:Show()
      else
        m.glow:Hide()
        m.label:Hide()
      end
    end
  end

  local s = summary(self)
  if #deals > 0 then
    local best = deals[1]
    s.text:SetText(("|cffffd100Coinwise|r  %d item%s here sell for more on the AH. Best: %s (+%s)"):format(
      #deals, #deals == 1 and "" or "s", ns.ItemInfo.name(best.itemID) or "?", Money.short(best.totalProfit)))
    s:Show()
  else
    s:Hide()
  end
end
