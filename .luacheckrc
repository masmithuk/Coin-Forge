std = "lua51"
max_line_length = 120
codes = true

-- WoW passes (addonName, namespace) to every file.
unused_args = false
allow_defined_top = false

exclude_files = { ".luarocks", "lua_modules" }

files["spec/"] = {
  std = "+busted",
  globals = { "_G" },
}

files["Main.lua"] = { globals = { "ForeverGoldDB", "SLASH_FOREVERGOLD1", "SLASH_FOREVERGOLD2", "SlashCmdList" } }

-- Read-only WoW API globals used by adapters and UI.
read_globals = {
  "C_AuctionHouse", "C_Timer", "C_NamePlate", "C_Item", "C_TradeSkillUI", "C_Map", "C_MerchantFrame", "C_Container", "C_SkillInfo",
  "TooltipDataProcessor", "Enum", "GameTooltip", "CreateFrame", "UIParent", "hooksecurefunc",
  "GetItemInfo", "GetItemInfoInstant", "GetRealmName", "UnitFactionGroup", "GetSubZoneText", "GetZoneText",
  "UnitGUID", "UnitName", "UnitIsPlayer", "UnitIsDead", "UnitCanAttack", "GetTime", "time", "date",
  "GetNumLootItems", "GetLootSlotLink", "GetLootSlotType", "GetLootSourceInfo", "GetLootSlotInfo",
  "GetNumSkillLines", "GetSkillLineInfo", "GetProfessions", "GetProfessionInfo",
  "GetNumTradeSkills", "GetTradeSkillInfo", "GetTradeSkillItemLink", "GetTradeSkillNumMade",
  "GetTradeSkillNumReagents", "GetTradeSkillReagentInfo", "GetTradeSkillReagentItemLink", "GetTradeSkillLine",
  "GetMerchantNumItems", "GetMerchantItemInfo", "GetMerchantItemLink", "GetMerchantItemID",
  "MerchantFrame", "MERCHANT_ITEMS_PER_PAGE", "AuctionHouseFrame", "GetMoney", "UnitFullName",
  "DEFAULT_CHAT_FRAME", "ITEM_QUALITY_COLORS", "GameFontNormal", "GameFontHighlightSmall",
  "FauxScrollFrame_Update", "FauxScrollFrame_GetOffset", "FauxScrollFrame_OnVerticalScroll",
}
