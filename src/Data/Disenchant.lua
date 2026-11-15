-- Disenchanting outcome tables.
--
-- Values are the original (vanilla 1.12) rules. WoW Forever may change them;
-- if it does, edit this file only - the logic in Core/Disenchant.lua reads it.
--
-- Uncommon bands: by item level. Armor yields mostly dust, weapons mostly
-- essence (the two chances are swapped for weapons).
local _, ns = ...

local I = {
  STRANGE_DUST = 10940, SOUL_DUST = 11083, VISION_DUST = 11137, DREAM_DUST = 11176, ILLUSION_DUST = 16204,
  LESSER_MAGIC = 10938, GREATER_MAGIC = 10939,
  LESSER_ASTRAL = 10998, GREATER_ASTRAL = 11082,
  LESSER_MYSTIC = 11134, GREATER_MYSTIC = 11135,
  LESSER_NETHER = 11174, GREATER_NETHER = 11175,
  LESSER_ETERNAL = 16202, GREATER_ETERNAL = 16203,
  SMALL_GLIMMERING = 10978, LARGE_GLIMMERING = 11084,
  SMALL_GLOWING = 11138, LARGE_GLOWING = 11139,
  SMALL_RADIANT = 11177, LARGE_RADIANT = 11178,
  SMALL_BRILLIANT = 14343, LARGE_BRILLIANT = 14344,
  NEXUS_CRYSTAL = 20725,
}

ns.Data.Disenchant = {
  items = I,

  -- { maxLevel, dust = {id, min, max}, essence = {...}, shard = {...},
  --   armor chances = {dust, essence, shard} }
  uncommon = {
    { maxLevel = 15, dust = { I.STRANGE_DUST, 1, 2 }, essence = { I.LESSER_MAGIC, 1, 2 },
      chances = { 0.80, 0.20, 0 } },
    { maxLevel = 20, dust = { I.STRANGE_DUST, 2, 3 }, essence = { I.GREATER_MAGIC, 1, 2 },
      shard = { I.SMALL_GLIMMERING, 1, 1 }, chances = { 0.75, 0.20, 0.05 } },
    { maxLevel = 25, dust = { I.STRANGE_DUST, 4, 6 }, essence = { I.LESSER_ASTRAL, 1, 2 },
      shard = { I.SMALL_GLIMMERING, 1, 1 }, chances = { 0.75, 0.15, 0.10 } },
    { maxLevel = 30, dust = { I.SOUL_DUST, 1, 2 }, essence = { I.GREATER_ASTRAL, 1, 2 },
      shard = { I.LARGE_GLIMMERING, 1, 1 }, chances = { 0.75, 0.20, 0.05 } },
    { maxLevel = 35, dust = { I.SOUL_DUST, 2, 5 }, essence = { I.LESSER_MYSTIC, 1, 2 },
      shard = { I.SMALL_GLOWING, 1, 1 }, chances = { 0.75, 0.20, 0.05 } },
    { maxLevel = 40, dust = { I.VISION_DUST, 1, 2 }, essence = { I.GREATER_MYSTIC, 1, 2 },
      shard = { I.LARGE_GLOWING, 1, 1 }, chances = { 0.75, 0.20, 0.05 } },
    { maxLevel = 45, dust = { I.VISION_DUST, 2, 5 }, essence = { I.LESSER_NETHER, 1, 2 },
      shard = { I.SMALL_RADIANT, 1, 1 }, chances = { 0.75, 0.20, 0.05 } },
    { maxLevel = 50, dust = { I.DREAM_DUST, 1, 2 }, essence = { I.GREATER_NETHER, 1, 2 },
      shard = { I.LARGE_RADIANT, 1, 1 }, chances = { 0.75, 0.20, 0.05 } },
    { maxLevel = 55, dust = { I.DREAM_DUST, 2, 5 }, essence = { I.LESSER_ETERNAL, 1, 2 },
      shard = { I.SMALL_BRILLIANT, 1, 1 }, chances = { 0.75, 0.20, 0.05 } },
    { maxLevel = 60, dust = { I.ILLUSION_DUST, 1, 2 }, essence = { I.GREATER_ETERNAL, 1, 2 },
      shard = { I.LARGE_BRILLIANT, 1, 1 }, chances = { 0.75, 0.20, 0.05 } },
    { maxLevel = 65, dust = { I.ILLUSION_DUST, 2, 5 }, essence = { I.GREATER_ETERNAL, 2, 3 },
      shard = { I.LARGE_BRILLIANT, 1, 1 }, chances = { 0.75, 0.20, 0.05 } },
  },

  -- Rare items give a shard, with a small chance of a Nexus Crystal at the top.
  rare = {
    { maxLevel = 25, outputs = { { I.SMALL_GLIMMERING, 1, 1, 1.0 } } },
    { maxLevel = 30, outputs = { { I.LARGE_GLIMMERING, 1, 1, 1.0 } } },
    { maxLevel = 35, outputs = { { I.SMALL_GLOWING, 1, 1, 1.0 } } },
    { maxLevel = 40, outputs = { { I.LARGE_GLOWING, 1, 1, 1.0 } } },
    { maxLevel = 45, outputs = { { I.SMALL_RADIANT, 1, 1, 1.0 } } },
    { maxLevel = 50, outputs = { { I.LARGE_RADIANT, 1, 1, 1.0 } } },
    { maxLevel = 55, outputs = { { I.SMALL_BRILLIANT, 1, 1, 1.0 } } },
    { maxLevel = 90, outputs = { { I.LARGE_BRILLIANT, 1, 1, 0.995 }, { I.NEXUS_CRYSTAL, 1, 1, 0.005 } } },
  },

  epic = {
    { maxLevel = 45, outputs = { { I.SMALL_RADIANT, 2, 4, 1.0 } } },
    { maxLevel = 50, outputs = { { I.LARGE_RADIANT, 2, 4, 1.0 } } },
    { maxLevel = 55, outputs = { { I.SMALL_BRILLIANT, 2, 4, 1.0 } } },
    { maxLevel = 60, outputs = { { I.NEXUS_CRYSTAL, 1, 1, 1.0 } } },
    { maxLevel = 90, outputs = { { I.NEXUS_CRYSTAL, 1, 2, 1.0 } } },
  },

  -- Enchanting skill needed, by item level (upper bound inclusive).
  skill = {
    { maxLevel = 20, skill = 1 }, { maxLevel = 25, skill = 25 }, { maxLevel = 30, skill = 50 },
    { maxLevel = 35, skill = 75 }, { maxLevel = 40, skill = 100 }, { maxLevel = 45, skill = 125 },
    { maxLevel = 50, skill = 150 }, { maxLevel = 55, skill = 175 }, { maxLevel = 60, skill = 200 },
    { maxLevel = 999, skill = 225 },
  },
}
