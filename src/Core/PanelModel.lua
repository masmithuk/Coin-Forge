-- PanelModel: turns opportunities into what the auction panel displays.
-- Kept free of frames so it can be tested.
local _, ns = ...

local PanelModel = {}
ns.PanelModel = PanelModel

PanelModel.LABELS = {
  all = "All",
  flip = "Flip",
  vendor = "Vendor",
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
