-- Provide a jls table that load modules

local function newIndexTable(name)
  local t = {}
  setmetatable(t, {
    __index = function(tt, key)
      local path = name..'.'..key
      local m = package.loaded[path]
      if m then
        return m
      end
      local status
      status, m = pcall(require, path)
      if status then
        return m
      end
      m = newIndexTable(path)
      tt[key] = m
      return m
    end
  })
  return t
end

return newIndexTable('jls')
