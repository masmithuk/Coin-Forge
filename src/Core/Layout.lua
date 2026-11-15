-- Layout: responsive sizing maths for list windows.
--
-- Columns declare a minimum width, a weight for sharing spare space and a
-- priority (1 = always shown; higher numbers are hidden first when narrow).
local _, ns = ...

local Layout = {}
ns.Layout = Layout

--- @param width available pixels
--- @param columns { {key, min, weight, priority}, ... } in display order
--- @return visible columns in display order: { key, x, width }
function Layout.columns(width, columns)
  local visible = {}
  for i, c in ipairs(columns) do visible[i] = c end

  local function minTotal()
    local t = 0
    for _, c in ipairs(visible) do t = t + c.min end
    return t
  end

  -- hide the lowest-priority column (last one on ties) until the rest fit
  while #visible > 1 and minTotal() > width do
    local drop = 1
    for i, c in ipairs(visible) do
      if c.priority >= visible[drop].priority then drop = i end
    end
    table.remove(visible, drop)
  end

  local spare = math.max(0, width - minTotal())
  local weights = 0
  for _, c in ipairs(visible) do weights = weights + (c.weight or 0) end

  local out, x, given, firstWeighted = {}, 0, 0, nil
  for i, c in ipairs(visible) do
    local extra = weights > 0 and math.floor(spare * (c.weight or 0) / weights) or 0
    given = given + extra
    if not firstWeighted and (c.weight or 0) > 0 then firstWeighted = i end
    out[i] = { key = c.key, width = c.min + extra }
  end
  -- rounding leftovers go to the first flexible column so widths sum exactly
  if firstWeighted then out[firstWeighted].width = out[firstWeighted].width + (spare - given) end
  for _, c in ipairs(out) do
    c.x = x
    x = x + c.width
  end
  return out
end

--- How many list rows fit in a frame of `height`, after `chrome` pixels of
--- header/footer. Always at least one.
function Layout.visibleRows(height, rowHeight, chrome)
  return math.max(1, math.floor((height - chrome) / rowHeight))
end
