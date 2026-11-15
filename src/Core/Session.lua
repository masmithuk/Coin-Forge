-- Session: a farming session tracker (gold gained, loot value, gold per hour).
local _, ns = ...

local Session = {}
Session.__index = Session
ns.Session = Session

--- @param clock function returning seconds
--- @param money current character money in copper
function Session.new(clock, money)
  local s = setmetatable({ clock = clock }, Session)
  s:reset(money)
  return s
end

function Session:reset(money)
  self.startTime = self.clock()
  self.startMoney = money or 0
  self.loot = 0
end

--- Adds the appraised value of looted items (coin is counted via money).
function Session:addLoot(value)
  self.loot = self.loot + (value or 0)
end

function Session:summary(money)
  local elapsed = self.clock() - self.startTime
  local gained = (money or 0) - self.startMoney
  local total = gained + self.loot
  local perHour = elapsed > 0 and math.floor(total * 3600 / elapsed) or 0
  return { elapsed = elapsed, money = gained, loot = self.loot, total = total, perHour = perHour }
end
