-- TradeSkillRecorder: remembers recipes when a profession window is open.
--
-- Storage (account-wide, so alts' recipes count too):
--   db.recipes[key] = { key, name, profession, outputItemID, outputQty,
--                       reagents = {{itemID, qty}}, crafters = { [charKey] = true } }
-- `crafters` lists only characters who have *learned* the recipe. WoW Forever's
-- recipe list also includes recipes you haven't learned; those are stored with
-- no crafter so they can be shown as "not learned".
--
-- Supports the classic trade skill API and, as a fallback, C_TradeSkillUI.
-- Collapsed categories hide their recipes in the classic window, so the
-- recorder simply records whatever is visible; re-opening adds the rest.
local _, ns = ...

local TradeSkillRecorder = {}
ns.TradeSkillRecorder = TradeSkillRecorder

local function store(db, charKey, recipe)
  db.recipes = db.recipes or {}
  local key = recipe.profession .. ":" .. recipe.outputItemID
  local existing = db.recipes[key]
  local learned = recipe.learned ~= false
  recipe.learned = nil
  recipe.key = key
  recipe.crafters = existing and existing.crafters or {}
  -- also corrects recipes an older version wrongly recorded as learned
  recipe.crafters[charKey] = learned or nil
  db.recipes[key] = recipe
end

local function readClassic()
  local profession = GetTradeSkillLine()
  if not profession or profession == "UNKNOWN" then return {} end
  local recipes = {}
  for i = 1, GetNumTradeSkills() do
    local name, kind = GetTradeSkillInfo(i)
    local outputItemID = kind ~= "header" and kind ~= "subheader" and ns.Api.itemIDFromLink(GetTradeSkillItemLink(i))
    if outputItemID then
      local minMade, maxMade = GetTradeSkillNumMade(i)
      local reagents, complete = {}, true
      for r = 1, GetTradeSkillNumReagents(i) do
        local _, _, count = GetTradeSkillReagentInfo(i, r)
        local reagentID = ns.Api.itemIDFromLink(GetTradeSkillReagentItemLink(i, r))
        if not reagentID or not count then complete = false break end
        reagents[#reagents + 1] = { itemID = reagentID, qty = count }
      end
      if complete then
        recipes[#recipes + 1] = {
          name = name, profession = profession, outputItemID = outputItemID,
          outputQty = ((minMade or 1) + (maxMade or minMade or 1)) / 2, reagents = reagents,
        }
      end
    end
  end
  return recipes
end

local function readModern()
  local api = C_TradeSkillUI
  local base = api.GetBaseProfessionInfo and api.GetBaseProfessionInfo()
  local profession = base and base.professionName
  if not profession then return {} end
  local recipes = {}
  for _, recipeID in ipairs(api.GetAllRecipeIDs() or {}) do
    local info = api.GetRecipeInfo and api.GetRecipeInfo(recipeID)
    local s = api.GetRecipeSchematic(recipeID, false)
    if s and s.outputItemID then
      local reagents = {}
      for _, slot in ipairs(s.reagentSlotSchematics or {}) do
        local first = slot.reagents and slot.reagents[1]
        if first and first.itemID then
          reagents[#reagents + 1] = { itemID = first.itemID, qty = slot.quantityRequired }
        end
      end
      recipes[#recipes + 1] = {
        name = s.name, profession = profession, outputItemID = s.outputItemID,
        outputQty = ((s.quantityMin or 1) + (s.quantityMax or s.quantityMin or 1)) / 2, reagents = reagents,
        learned = not info or info.learned ~= false,
      }
    end
  end
  return recipes
end

--- Records every visible recipe. Returns how many were recorded.
function TradeSkillRecorder.record(db, charKey)
  local recipes
  if GetNumTradeSkills and GetTradeSkillLine then
    recipes = readClassic()
  elseif ns.Api.has("C_TradeSkillUI.GetAllRecipeIDs") then
    recipes = readModern()
  else
    recipes = {}
  end
  for _, recipe in ipairs(recipes) do store(db, charKey, recipe) end
  return #recipes
end

--- What the open profession window looks like to the recorder (for /cw recipes):
--- which API path is used and how many recipes the game says are learned.
function TradeSkillRecorder.diagnose()
  local d = {
    hasClassic = (GetNumTradeSkills and GetTradeSkillLine) and true or false,
    hasModern = ns.Api.has("C_TradeSkillUI.GetAllRecipeIDs"),
    hasLearnedFlag = false, total = 0, learned = 0, unlearned = 0,
  }
  d.path = d.hasClassic and "classic" or (d.hasModern and "modern" or "none")
  if d.hasClassic then
    d.profession = GetTradeSkillLine()
    d.total = GetNumTradeSkills() or 0
  end
  if d.hasModern then
    local api = C_TradeSkillUI
    local base = api.GetBaseProfessionInfo and api.GetBaseProfessionInfo()
    d.profession = d.profession or (base and base.professionName)
    local ids = api.GetAllRecipeIDs() or {}
    d.modernTotal = #ids
    if not d.hasClassic then d.total = #ids end
    for _, id in ipairs(ids) do
      local info = api.GetRecipeInfo and api.GetRecipeInfo(id)
      if info and info.learned ~= nil then d.hasLearnedFlag = true end
      if info and info.learned == false then d.unlearned = d.unlearned + 1 else d.learned = d.learned + 1 end
    end
  end
  return d
end

--- Recorded recipes learned by at least one of your characters, with crafter
--- names and whether `charKey` knows them.
--- @param opts { includeUnlearned = true } to also list recipes nobody has learned
function TradeSkillRecorder.recipesFor(db, charKey, opts)
  local includeUnlearned = opts and opts.includeUnlearned
  local list = {}
  for _, r in pairs(db.recipes or {}) do
    local crafters = {}
    for name in pairs(r.crafters or {}) do crafters[#crafters + 1] = name end
    table.sort(crafters)
    if #crafters > 0 or includeUnlearned then
      list[#list + 1] = {
        key = r.key, name = r.name, profession = r.profession, outputItemID = r.outputItemID,
        outputQty = r.outputQty, reagents = r.reagents, crafters = crafters,
        knownByPlayer = r.crafters and r.crafters[charKey] == true or false,
        learnedBySomeone = #crafters > 0,
      }
    end
  end
  table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
  return list
end
