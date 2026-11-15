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
  if GetNumSkillLines and GetSkillLineInfo then return fromSkillLines() end
  if GetProfessions and GetProfessionInfo then return fromProfessions() end
  return {}
end
