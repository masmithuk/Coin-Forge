-- PanelModel: turns opportunities into what the auction panel displays.
-- Kept free of frames so it can be tested.
local _, ns = ...

local PanelModel = {}
ns.PanelModel = PanelModel

PanelModel.LABELS = {
  all = "All",
  flip = "Flip",
  vendor = "Vendor",
  vendorFlip = "From vendor",
  disenchant = "Disenchant",
  conversion = "Convert",
  craft = "Craft",
  craftInstead = "Make it",
  arbitrage = "Other AH",
}

-- One-line explanation per kind, shown when a tab is hovered.
PanelModel.HELP = {
  all = "Every opportunity, most profitable first.",
  flip = "Listed well under its usual price. Buy and relist.",
  vendor = "Cheaper than a vendor pays for it. Buy and vendor.",
  vendorFlip = "A vendor you've visited sells it for less than the AH pays. Buy there, list here.",
  disenchant = "Worth more as enchanting materials than as an item.",
  conversion = "Combine or split essences for a profit.",
  craft = "Buy the reagents now, craft, and sell the result.",
  craftInstead = "Listed for more than it costs to make yourself.",
  arbitrage = "Sells for more on another auction house.",
}

function PanelModel.filter(opps, filter)
  local out = {}
  for _, o in ipairs(opps) do
    local kindOk = filter.kind == nil or filter.kind == "all" or o.kind == filter.kind
    local doOk = not filter.onlyCanDo or o.canDo
    if kindOk and doOk then out[#out + 1] = o end
  end
  return out
end

--- @param nameOf function(itemID) -> item name (may be nil while loading)
function PanelModel.row(o, nameOf)
  return {
    name = o.name or nameOf(o.itemID) or ("item:" .. o.itemID),
    kindLabel = PanelModel.LABELS[o.kind] or o.kind,
    price = o.maxPrice and ns.Money.short(o.maxPrice) or "",
    qty = o.qty and tostring(o.qty) or "",
    profit = ns.Money.short(o.profit),
    note = o.note or "",
    canDo = o.canDo,
  }
end

function PanelModel.summary(opps)
  local s = { count = #opps, profit = 0, byKind = {} }
  for _, o in ipairs(opps) do
    s.profit = s.profit + o.profit
    s.byKind[o.kind] = (s.byKind[o.kind] or 0) + 1
  end
  return s
end

--- Footer text for the deals list. It always says what the "Only what I can do"
--- toggle is doing, so ticking it never looks like it did nothing.
--- @param opps every opportunity (unfiltered)
--- @param filter { kind, onlyCanDo }
function PanelModel.footer(opps, filter)
  local inTab = PanelModel.filter(opps, { kind = filter.kind })
  if #inTab == 0 then return "" end
  local doable = PanelModel.filter(inTab, { onlyCanDo = true })
  local hidden = #inTab - #doable
  local shown = filter.onlyCanDo and doable or inTab

  if #shown == 0 then
    return ("Nothing here you can do. %d hidden that need a profession or skill you don't have."):format(hidden)
  end
  local s = PanelModel.summary(shown)
  local text = ("%d deal%s, about %s profit. Click a row to find it."):format(
    s.count, s.count == 1 and "" or "s", ns.Money.short(s.profit))
  if hidden == 0 then return text .. " (you can do all of these)" end
  if filter.onlyCanDo then return text .. (" %d hidden that you can't do."):format(hidden) end
  return text .. (" %d need a profession or skill you don't have."):format(hidden)
end

--- Tabs to show: "All" plus only the kinds that have results, so the
--- panel never shows empty tabs.
function PanelModel.tabs(opps)
  local s = PanelModel.summary(opps)
  local tabs = { { kind = "all", label = PanelModel.LABELS.all, count = tostring(s.count) } }
  for _, kind in ipairs(ns.Opportunities.KINDS) do
    if s.byKind[kind] then
      tabs[#tabs + 1] = { kind = kind, label = PanelModel.LABELS[kind], count = tostring(s.byKind[kind]) }
    end
  end
  return tabs
end
