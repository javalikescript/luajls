local logger = require('jls.lang.logger')

local Logger = logger:getClass()
local level = logger:getLevel()

local modMap = {}

local function configure(name, value)
  local mod = string.match(name, '^(.+)%.level$')
  if mod then
    modMap[mod] = Logger.levelFromString(value)
  end
end

local hasLuv, luvLib = pcall(require, 'luv')
if hasLuv and luvLib.os_environ then
  local env = luvLib.os_environ()
  for key, value in pairs(env) do
    local name = string.match(key, '^JLS_LOGGER_(.+)$')
    if name then
      configure(name, value)
    end
  end
end

local filename = os.getenv('JLS_LOGGER_FILE')
if filename then
  local f = io.open(filename, 'r')
  if f then
    local data = f:read('*a')
    f:close()
    if data then
      for line in string.gmatch(data, '[^\r\n]+') do
        local name, value = string.match(line, '^%s*([%w%.%-]+)%s*=%s*(.*)%s*$')
        if name then
          configure(name, value)
        end
      end
    end
  end
end

return function(name)
  local l = level
  if name then
    l = modMap[name]
    if not l then
      l = level
    end
  end
  return Logger:new(name, l)
end
