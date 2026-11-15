-- Fees: the auction house's cut of every sale.
-- Deposits are refunded when an auction sells, so they are not modelled.
local _, ns = ...

local Fees = {}
ns.Fees = Fees

Fees.FACTION_CUT = 0.05
Fees.NEUTRAL_CUT = 0.15

function Fees.cutRate(isNeutral)
  return isNeutral and Fees.NEUTRAL_CUT or Fees.FACTION_CUT
end

--- What you actually receive when something sells for `price`.
function Fees.net(price, isNeutral)
  return math.floor(price * (1 - Fees.cutRate(isNeutral)))
end
