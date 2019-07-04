--- Provide string helper functions.
-- @module jls.util.strings

local strings = {}


--- Returns a list of strings split at each pattern.
-- @tparam string value The string to split.
-- @tparam string pattern The pattern used to split the string.
-- @tparam boolean plain true to find the pattern as a plain string.
-- @treturn table a list of strings split at each pattern.
function strings.split(value, pattern, plain)
  local list = {}
  local s = #value
  local p = 1
  while p <= s do
    local pStart, pEnd = string.find(value, pattern, p, plain)
    if pStart then
      table.insert(list, string.sub(value, p, pStart - 1))
      p = pEnd + 1
    else
      table.insert(list, string.sub(value, p))
      break
    end
  end
  return list
end

--[[
function strings.compareToIgnoreCase(s1, s2) end
function strings.equalsIgnoreCase(s1, s2) end
function strings.endsWith(s1, s2) end
function strings.startsWith(s1, s2) end
function strings.trim(s) end
function strings.format(s) end
]]

return strings
