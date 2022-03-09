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

local LOG_FILE = io.stderr

local LOG_EOL = '\n'
if string.sub(package.config, 1, 1) == '\\' or string.find(package.cpath, '%.dll') then
  LOG_EOL = '\r\n'
end

local writeLog = function(text)
  LOG_FILE:write(text)
  LOG_FILE:write(LOG_EOL)
  LOG_FILE:flush()
end

local formatLog = function(logger, level, message)
  return os.date('%Y-%m-%dT%H:%M:%S', os.time())..' '..tostring(level)..' '..message
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
    local tv = type(v)
    local pn = prefix..name..' (' .. tv .. ')'
    -- There are eight basic types in Lua: nil, boolean, number, string, userdata, function, thread, and table.
    if tv == 'string' then
      p(pn..': "'..v..'"')
    elseif tv == 'table' then
      local empty = next(v) == nil
      if empty then
        p(pn..': empty')
      else
        p(pn..':')
        if level < maxLevel then
          for k in pairs(v) do
            dump(p, v[k], '['..k..']', maxLevel, prefix..indent, indent, level + 1)
          end
        else
          p(prefix..indent..'...')
        end
      end
    else
      local mt = getmetatable(v)
      p(pn..': '..tostring(v))
      if mt then
        dump(p, mt, 'metatable', maxLevel, prefix..indent, indent, level + 1)
      end
    end
  end

  --- Logs the specified message with the specified level.
  -- @param level The log level.
  -- @param message The log message.
  function logger:log(level, message)
    if level >= self.level then
      if type(message) == 'string' then
        writeLog(formatLog(self, level, message))
      else
        dump(writeLog, message, 'value', 5, '', '  ', 0)
      end
    end
  end

  function logger:logTable(level, value, name, depth)
    if level >= self.level then
      dump(writeLog, value, name or 'value', depth or 5, '', '  ', 0)
    end
  end

  function logger:logTraceback(level, message)
    if level >= self.level then
      writeLog(debug.traceback(message, 2))
    end
  end

  function logger:dump(value, name, depth)
    self:logTable(DEBUG, value, name, depth)
  end

  function logger:traceback(message)
    if DEBUG >= self.level then
      writeLog(debug.traceback(message, 2))
    end
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

  -- shortcuts
  for k, v in pairs(LEVEL) do
    logger[k] = v
  end

end)

Logger.LEVEL = LEVEL

Logger.EOL = LOG_EOL

Logger.levelFromString = levelFromString
Logger.levelToString = levelToString

function Logger.getLogWriter()
  return writeLog
end
function Logger.setLogWriter(logWriterFn)
  writeLog = logWriterFn
end

function Logger.getLogFormatter()
  return formatLog
end
function Logger.setLogFormatter(logFormatterFn)
  formatLog = logFormatterFn
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