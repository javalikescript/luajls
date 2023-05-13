---@diagnostic disable-next-line: deprecated
local table_unpack = table.unpack or _G.unpack

local function randomChars(len, from, to)
  from = from or 0
  to = to or 255
  if len <= 10 then
    local bytes = {}
    for _ = 1, len do
      table.insert(bytes, math.random(from, to))
    end
    return string.char(table_unpack(bytes))
  end
  local parts = {}
  for _ = 1, len / 10 do
    table.insert(parts, randomChars(10, from, to))
  end
  table.insert(parts, randomChars(len % 10, from, to))
  return table.concat(parts)
end

return randomChars
