--[[--
Returns the default logger implementation.

A Logger object is used to record events during the execution of Lua modules.
This default implementation provides a simple way for module owner to expose debugging information and for module user to access this information.
This default implementation could be configured to redirect log messages to another logging facility.

The default log level is warning.
The default formatting consists in prefixing the message by the date time as ISO 8601 and the log level.
The default writing consists in printing the log message to the standard error stream, adding a new line and flushing.

The JLS\_LOGGER\_LEVEL environment variable could be used to indicate the log level to use.


@usage
local logger = require('jls.lang.logger')
logger:info('Some usefull information message')

if logger:isLoggable(logger.FINE) then
  logger:fine('Some fine message')
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

local LEVEL_NAMES = {}
for k, v in pairs(LEVEL) do
  LEVEL_NAMES[v] = k
end

local function levelFromString(value)
  return LEVEL[string.upper(value)]
end

local function levelToString(value)
  return LEVEL_NAMES[value] or ''
end

local function parseLevel(level, fallback)
  if type(level) == 'number' then
    return level
  elseif type(level) == 'string' then
    local l = levelFromString(level)
    if l then
      return l
    end
  end
  if fallback then
    return fallback
  end
  error('Invalid logger level "'..tostring(level)..'"')
end
local LOG_FILE = io.stderr

local LOG_EOL = '\n'
if string.sub(package.config, 1, 1) == '\\' or string.find(package.cpath, '%.dll') then
  LOG_EOL = '\r\n'
end

local function defaultLogRecorder(logger, time, level, message)
  LOG_FILE:write(os.date('%Y-%m-%dT%H:%M:%S', time)..' '..levelToString(level)..' '..message..LOG_EOL)
  LOG_FILE:flush()
end
local LOG_RECORD = defaultLogRecorder

local function dumpToList(l, v, name, maxLevel, prefix, indent, level)
  local tv = type(v)
  local pn = prefix..name..' (' .. tv .. ')'
  -- There are eight basic types in Lua: nil, boolean, number, string, userdata, function, thread, and table.
  if tv == 'string' then
    table.insert(l, pn..': "'..v..'"')
  elseif tv == 'table' then
    local empty = next(v) == nil
    if empty then
      table.insert(l, pn..': empty')
    else
      table.insert(l, pn..':')
      if level < maxLevel then
        for k in pairs(v) do
          dumpToList(l, v[k], '['..k..']', maxLevel, prefix..indent, indent, level + 1)
        end
      else
        table.insert(l, prefix..indent..'...')
      end
    end
  else
    table.insert(l, pn..': '..tostring(v))
    local mt = getmetatable(v)
    if mt then
      dumpToList(l, mt, 'metatable', maxLevel, prefix..indent, indent, level + 1)
    end
  end
end

local function dumpToString(v, name, maxLevel, prefix, indent, level)
  local l =  {}
  dumpToList(l, v, name, maxLevel, prefix, indent, level)
  return table.concat(l, LOG_EOL)
end

local function log(logger, level, message, ...)
  if type(message) == 'string' and string.find(message, '%', 1, true) and select('#', ...) > 0 then
    message = string.format(message, ...)
  else
    local args = table.pack(message, ...)
    local l =  {}
    for i = 1, args.n do
      local v = args[i]
      if type(v) == 'string' then
        table.insert(l, v)
      else
        dumpToList(l, v, '#'..tostring(i), 5, '', '  ', 0)
      end
    end
    message = table.concat(l, LOG_EOL)
  end
  LOG_RECORD(logger, os.time(), level, message)
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

  -- shortcuts
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
    self.level = parseLevel(level)
  end

  --- Tells wether or not a message of the specified level will be logged by this logger. 
  -- @tparam number level The log level to check.
  -- @treturn boolean true if a message of the specified level will be logged by this logger.
  function logger:isLoggable(level)
    return level >= self.level
  end

  --- Logs the specified message with the specified level.
  -- When message is a string then additional arguments are formatted using string.format
  -- @param level The log level.
  -- @param message The log message.
  function logger:log(level, message, ...)
    local l = parseLevel(level)
    if l >= self.level then
      log(self, l, message, ...)
    end
  end

  -- for compatibility, deprecated
  function logger:logopt(level, message, ...)
    local time = os.time()
    if time > (self.time or 0) then
      local l = parseLevel(level)
      if l >= self.level then
        self.time = time
        log(self, l, message, ...)
      end
    end
  end

  -- for compatibility, deprecated
  function logger:logTable(level, value, name, depth)
    if parseLevel(level) >= self.level then
      LOG_FILE:write(dumpToString(value, name or 'value', depth or 5, '', '  ', 0))
      LOG_FILE:flush()
    end
  end

  -- for compatibility, deprecated
  function logger:logTraceback(level, message)
    local l = parseLevel(level)
    if l >= self.level then
      log(self, l, debug.traceback(message, 2))
    end
  end

  -- for compatibility, deprecated
  function logger:dump(value, name, depth)
    self:logTable(DEBUG, value, name, depth)
  end

  -- for compatibility, deprecated
  function logger:traceback(message)
    if DEBUG >= self.level then
      log(self, DEBUG, debug.traceback(message, 2))
    end
  end

  --- Logs the specified message with the ERROR level.
  -- @param message The log message.
  function logger:error(message, ...)
    if ERROR >= self.level then
      log(self, ERROR, message, ...)
    end
  end

  --- Logs the specified message with the WARN level.
  -- @param message The log message.
  function logger:warn(message, ...)
    if WARN >= self.level then
      log(self, WARN, message, ...)
    end
  end

  --- Logs the specified message with the INFO level.
  -- @param message The log message.
  function logger:info(message, ...)
    if INFO >= self.level then
      log(self, INFO, message, ...)
    end
  end

  --- Logs the specified message with the CONFIG level.
  -- @param message The log message.
  function logger:config(message, ...)
    if CONFIG >= self.level then
      log(self, CONFIG, message, ...)
    end
  end

  --- Logs the specified message with the DEBUG level.
  -- @param message The log message.
  function logger:debug(message, ...)
    if DEBUG >= self.level then
      log(self, DEBUG, message, ...)
    end
  end

  --- Logs the specified message with the FINE level.
  -- @param message The log message.
  function logger:fine(message, ...)
    if FINE >= self.level then
      log(self, FINE, message, ...)
    end
  end

  --- Logs the specified message with the FINER level.
  -- @param message The log message.
  function logger:finer(message, ...)
    if FINER >= self.level then
      log(self, FINER, message, ...)
    end
  end

  --- Logs the specified message with the FINEST level.
  -- @param message The log message.
  function logger:finest(message, ...)
    if FINEST >= self.level then
      log(self, FINEST, message, ...)
    end
  end

  -- shortcuts
  for k, v in pairs(LEVEL) do
    logger[k] = v
  end

end)

Logger.LEVEL = LEVEL

Logger.EOL = LOG_EOL

Logger.levelFromString = levelFromString
Logger.levelToString = levelToString

function Logger.getLogFile()
  return LOG_FILE
end
function Logger.setLogFile(logFile)
  LOG_FILE = logFile or io.stderr
end

function Logger.getLogRecorder()
  return LOG_RECORD
end
function Logger.setLogRecorder(logRecorderFn)
  LOG_RECORD = logRecorderFn or defaultLogRecorder
end

--- @section end

-- the module is the default instance of Logger
local logger = Logger:new()

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