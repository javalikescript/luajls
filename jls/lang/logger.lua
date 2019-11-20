--[[--
Returns the default logger implementation.

A Logger object is used to log messages for a specific system or application component.
The JLS_LOGGER_LEVEL environment variable could be used to indicate the log level to use.
@usage
local logger = require('jls.lang.logger')
logger:info('Some usefull information message')

if logger:isLoggable(logger.DEBUG) then
  logger:debug('Some debug message')
end

@module jls.lang.logger
@pragma nostrip
]]

--- The available log levels.
-- The level fields are also provided as shortcut to the default implementation.
-- @table LEVEL
local LEVEL = {
  ERROR = 100, --- The error level is the highest level
  WARN = 90, --- The warning level
  INFO = 80, --- The information level
  CONFIG = 70, --- The configuration level
  FINE = 60, --- The fine level
  FINER = 50, --- The finer level
  FINEST = 40, --- The finest level
  DEBUG = 30, --- The debug level
  -- Do not use, shall be removed
  ALL = 0 --- The all level is the lowest level
}

local function levelFromString(value)
  return LEVEL[string.upper(value)]
end

local function levelToString(value)
  for k, v in pairs(LEVEL) do
    if v == value then
      return k
    end
  end
  return ''
end

--- A Logger class.
-- A Logger object is used to log messages for a specific system or application component.
-- @type Logger
local Logger = require('jls.lang.class').create(function(logger)

  -- shortcuts
  local ERROR = LEVEL.ERROR
  local WARN = LEVEL.WARN
  local INFO = LEVEL.INFO
  local CONFIG = LEVEL.CONFIG
  local DEBUG = LEVEL.DEBUG
  local FINE = LEVEL.FINE
  local FINER = LEVEL.FINER
  local FINEST = LEVEL.FINEST

  -- shortcut
  logger.LEVEL = LEVEL

  --- Creates a new logger with the specified level.
  -- @function Logger:new
  -- @param level The log level.
  -- @return a new logger
  -- @usage
  --local console = require('jls.lang.logger'):getClass():new()
  --console:info('Some usefull information message')
  function logger:initialize(level)
    self.level = level or WARN
  end

  --- Returns the log level for this logger.
  -- @return the log level for this logger.
  function logger:getLevel()
    return self.level
  end

  --- Sets the log level for this logger.
  -- @param level The log level.
  function logger:setLevel(level)
    if type(level) == 'number' then
      self.level = level
    elseif type(level) == 'string' then
      local l = levelFromString(level)
      if l then
        self.level = l
      else
        error('Invalid logger level "'..level..'"')
      end
    end
  end

  --- Tells wether or not a message of the specified level will be logged by this logger. 
  -- @param level The log level to check.
  -- @return true if a message of the specified level will be logged by this logger.
  function logger:isLoggable(level)
    return level >= self.level
  end

  local function dump(p, v, name, maxLevel, prefix, indent, level)
    name = name or ''
    maxLevel = maxLevel or 1
    prefix = prefix or ''
    indent = indent or '  '
    level = level or 0
    local tv = type(v)
    local pn = prefix..name..' (' .. tv .. ')'
    -- There are eight basic types in Lua: nil, boolean, number, string, userdata, function, thread, and table.
    if tv == 'string' then
      p(pn..': "'..v..'"')
    elseif tv == 'boolean' or tv == 'number' or tv == 'nil' then
      p(pn..': '..tostring(v))
    elseif tv == 'table' then
      p(pn..':')
      if level < maxLevel then
        for k in pairs(v) do
          dump(p, v[k], '['..k..']', maxLevel, prefix..indent, indent, level + 1)
        end
      end
    else
      p(pn)
    end
  end

  --- Logs the specified message with the specified level.
  -- @param level The log level.
  -- @param message The log message.
  function logger:log(level, message)
    if level >= self.level then
      if type(message) == 'string' then
        print(os.date('%Y-%m-%dT%H:%M:%S', os.time())..' '..tostring(level)..' '..message)
      else
        dump(print, message, 'value')
      end
    end
  end

  function logger:logTable(level, value, name, depth)
    if level >= self.level then
      dump(print, value, name or 'value', depth, '', '  ', 0)
    end
  end

  function logger:dump(value, name, depth)
    self:logTable(DEBUG, value, name, depth)
  end

  --- Logs the specified message with the ERROR level.
  -- @param message The log message.
  function logger:error(message)
    self:log(ERROR, message)
  end

  --- Logs the specified message with the WARN level.
  -- @param message The log message.
  function logger:warn(message)
    self:log(WARN, message)
  end

  --- Logs the specified message with the INFO level.
  -- @param message The log message.
  function logger:info(message)
    self:log(INFO, message)
  end

  --- Logs the specified message with the CONFIG level.
  -- @param message The log message.
  function logger:config(message)
    self:log(CONFIG, message)
  end

  --- Logs the specified message with the DEBUG level.
  -- @param message The log message.
  function logger:debug(message)
    self:log(DEBUG, message)
  end

  --- Logs the specified message with the FINE level.
  -- @param message The log message.
  function logger:fine(message)
    self:log(FINE, message)
  end

  --- Logs the specified message with the FINER level.
  -- @param message The log message.
  function logger:finer(message)
    self:log(FINER, message)
  end

  --- Logs the specified message with the FINEST level.
  -- @param message The log message.
  function logger:finest(message)
    self:log(FINEST, message)
  end
end)

Logger.LEVEL = LEVEL

Logger.levelFromString = levelFromString
Logger.levelToString = levelToString

--- @section end

-- the module is the default instance of Logger
local logger = Logger:new()

-- shortcuts
for k, v in pairs(LEVEL) do
  logger[k] = v
end

--logger.Logger = Logger -- use logger:getClass()

local jlsLoggerLevel = os.getenv('JLS_LOGGER_LEVEL')
if jlsLoggerLevel then
  local l = levelFromString(jlsLoggerLevel)
  if l then
    logger:setLevel(l)
    logger:info('set log level to '..levelToString(l)..' based on the JLS_LOGGER_LEVEL environment variable')
  end
end

return logger