local rootLogger = require('jls.lang.logger')

local Logger = rootLogger:getClass()
local rootLevel = rootLogger:getLevel()

local levelMap = {}

local function configure(name, value)
  local mod = string.match(name, '^(.+)%.level$')
  if mod then
    levelMap[mod] = Logger.levelFromString(value)
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

local loggerMap = {} -- TODO Use weak table

function rootLogger:setLevel(level)
  rootLevel = Logger.parseLevel(level)
  self.level = rootLevel
  for _, lgr in pairs(loggerMap) do
    lgr:setLevel(rootLevel)
  end
end

return function(name)
  if name then
    local lgr = loggerMap[name]
    if lgr then
      return lgr
    end
    local lvl = levelMap[name]
    lgr = Logger:new(name, lvl or rootLevel)
    loggerMap[name] = lgr
    return lgr
  end
  return rootLogger
end
