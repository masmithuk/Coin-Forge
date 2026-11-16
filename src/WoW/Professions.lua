-- Professions: the current character's profession skill levels.
local _, ns = ...

local Professions = {}
ns.Professions = Professions

-- enUS profession names we care about.
Professions.NAMES = {
  Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true,
  Herbalism = true, Leatherworking = true, Mining = true, Skinning = true,
  Tailoring = true, Cooking = true, ["First Aid"] = true, Fishing = true,
  Jewelcrafting = true, Inscription = true,
}

-- WoW Forever replaced the global skill line API with C_SkillInfo. Its list
-- only includes lines under expanded headers, so expand collapsed ones first
-- (back to front: expanding inserts lines and shifts later indices).
local function fromSkillInfo()
  local api = C_SkillInfo
  if api.ExpandSkillHeader then
    for i = api.GetNumSkillLines(), 1, -1 do
      local line = api.GetSkillLineInfo(i)
      if line and line.isHeader and line.isCollapsed then api.ExpandSkillHeader(i) end
    end
  end
  local skills = {}
  for i = 1, api.GetNumSkillLines() do
    local line = api.GetSkillLineInfo(i)
    if line and not line.isHeader and Professions.NAMES[line.name] then skills[line.name] = line.rank end
  end
  return skills
end

local function fromSkillLines()
  local skills = {}
  for i = 1, GetNumSkillLines() do
    local name, isHeader, _, rank = GetSkillLineInfo(i)
    if not isHeader and Professions.NAMES[name] then skills[name] = rank end
  end
  return skills
end

local function fromProfessions()
  local skills = {}
  local indices = { GetProfessions() }
  for i = 1, 5 do
    local index = indices[i]
    if index then
      local name, _, rank = GetProfessionInfo(index)
      if name then skills[name] = rank end
    end
  end
  return skills
end

--- @return { [professionName] = skillRank }
function Professions.read()
  if ns.Api.has("C_SkillInfo.GetNumSkillLines") and ns.Api.has("C_SkillInfo.GetSkillLineInfo") then
    return fromSkillInfo()
  end
  if GetNumSkillLines and GetSkillLineInfo then return fromSkillLines() end
  if GetProfessions and GetProfessionInfo then return fromProfessions() end
  return {}
end
