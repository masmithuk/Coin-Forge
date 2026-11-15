-- VendorAnalysis: which items on a merchant are worth more on the AH.
local _, ns = ...

local VendorAnalysis = {}
ns.VendorAnalysis = VendorAnalysis

--- @param merchantItems { {index, itemID, price, stack, available} }
--   price is per purchase of `stack` items; available is -1 for unlimited.
--- @param ctx { value(itemID), history(itemID), cutRate, settings }
--- @return profitable items, best first:
--   { index, itemID, profit (per purchase), totalProfit, limited, strong }
function VendorAnalysis.evaluate(merchantItems, ctx)
  local list = {}
  for _, m in ipairs(merchantItems) do
    local value = m.itemID and ctx.value(m.itemID)
    if value and m.price > 0 and ctx.history(m.itemID) >= ctx.settings.minHistoryDays then
      local profit = math.floor(value * (1 - ctx.cutRate) * (m.stack or 1) - m.price)
      if profit > 0 then
        local limited = (m.available or -1) > 0
        local total = limited and profit * m.available or profit
        list[#list + 1] = {
          index = m.index, itemID = m.itemID, profit = profit, totalProfit = total,
          limited = limited, strong = total >= ctx.settings.minProfit,
        }
      end
    end
  end
  table.sort(list, function(a, b) return a.totalProfit > b.totalProfit end)
  return list
end
