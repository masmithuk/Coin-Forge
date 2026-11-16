-- Test helper: loads addon files the same way the WoW client does.
--
-- WoW passes every file two varargs: the addon name and a private namespace
-- table shared by all files of the addon. We read the file list from the .toc
-- so tests always load modules in the same order as the game.

local M = {}

local ADDON_NAME = "CoinForge"
local TOC_PATH = "CoinForge.toc"

--- Returns the ordered list of source files declared in the .toc.
-- @param prefix optional path prefix filter, e.g. "src/Core/"
function M.tocFiles(prefix)
  local files = {}
  for line in io.lines(TOC_PATH) do
    local path = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
    if path and (not prefix or path:sub(1, #prefix) == prefix) then
      files[#files + 1] = path
    end
  end
  return files
end

--- Loads files into a fresh namespace and returns it.
function M.load(files, ns)
  ns = ns or {}
  for _, path in ipairs(files) do
    local chunk = assert(loadfile(path))
    chunk(ADDON_NAME, ns)
  end
  return ns
end

--- Loads all pure Core and Data modules (no WoW globals needed).
function M.loadCore()
  -- keep toc order: Data files must load before the Core modules that read them
  local files = {}
  for _, f in ipairs(M.tocFiles()) do
    if f:find("^src/Core/") or f:find("^src/Data/") then files[#files + 1] = f end
  end
  return M.load(files)
end

--- Loads Core plus the named WoW adapter / UI files.
function M.loadWith(extra)
  local ns = M.loadCore()
  return M.load(extra, ns)
end

return M
