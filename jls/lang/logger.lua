--[[--
Returns the default logger implementation.

A Logger object is used to record events during the execution of Lua modules.
This default implementation provides a simple way for module owner to expose debugging information and for module user to access this information.
This default implementation could be configured to redirect log messages to another logging facility.

The default log level is warning.
The default formatting consists in prefixing the message by the date time as ISO 8601, the module name and the log level.
The default writing consists in printing the log message to the standard error stream, adding a new line and flushing.

The `JLS_LOGGER_LEVEL` environment variable could be used to indicate the log level to use.
You could use comma separated values of module name and associated level, "`INFO,jls.net:FINE`".
Another option is the lua execute argument: `lua -e "require('jls.lang.logger'):setConfig('info,secure:fine')"`

@usage
local logger = require('jls.lang.logger'):get(...) -- require will pass the module name
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

local function trunc(s, l)
  if #s > l then
    return '+'..string.sub(s, 1-l)
  end
  return s
end

local function trim(value)
  return (string.gsub(string.gsub(value, '^%s+', ''), '%s+$', ''))
end


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
  if type(level) == 'number' and LEVEL_NAMES[level] then
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

local os_date = os.date
local os_time = os.time
local string_format = string.format
local string_find = string.find
local string_byte = string.byte
local LOG_FILE = io.stderr
local LEVEL_LEN = 6
local NAME_LEN = 20

local LOG_EOL = '\n'
if string.sub(package.config, 1, 1) == '\\' then
  LOG_EOL = '\r\n'
end
local LOG_THREAD = os.getenv('JLS_LOGGER_THREAD') and string.format(' %p', coroutine.running()) or ''
local LOG_FORMAT = '%s'..LOG_THREAD..' %'..NAME_LEN..'.'..NAME_LEN..'s %-'..LEVEL_LEN..'s %s'..LOG_EOL

local function defaultLogRecorder(logger, time, level, message)
  LOG_FILE:write(string_format(LOG_FORMAT, os_date('%Y-%m-%dT%H:%M:%S', time), logger.sname, LEVEL_NAMES[level], message))
  LOG_FILE:flush()
end
local LOG_RECORD = defaultLogRecorder

local format_t
-- lazy loading tables on first call
format_t = function(...)
  local status, tables = pcall(require, 'jls.util.tables')
  if status then
    local stringify = tables.stringify
    format_t = function(value, up)
      return stringify(value, up and 2 or nil, true)
    end
  else
    format_t = tostring
  end
  return format_t(...)
end

local function ctoh(c)
  return string_format('%02x', string_byte(c))
end
local function ctoH(c)
  return string_format('%02X', string_byte(c))
end

local function log(logger, level, message, ...)
  local n = select('#', ...)
  if type(message) == 'string' then
    if n > 0 and string_find(message, '%', 1, true) then
      if string_find(message, '%%[ltTxX]') then -- cdiuoxXaAfeEgGpqs
        local args = {...}
        local i = 0
        message = string.gsub(message, '%%(.)', function(s)
          if s == '%' then
            return '%%'
          end
          if i < n then
            i = i + 1
            if s == 't' or s == 'T' then
              args[i] = format_t(args[i], s == 'T')
              return '%s'
            elseif s == 'l' then
              local v = args[i]
              if type(v) == 'string' then
                args[i] = #v
              elseif type(v) == 'table' then
                local l = #v
                if l == 0 and getmetatable(v) == nil then
                  for _ in pairs(v) do
                    l = l + 1
                  end
                end
                args[i] = l
              else
                args[i] = type(v)
              end
              return '%s'
            elseif s == 'x' or s == 'X' then
              local v = args[i]
              if type(v) == 'string' then
                args[i] = string.gsub(v, '.', s == 'X' and ctoH or ctoh)
                return '%s'
              elseif v == nil then
                args[i] = 'nil'
                return '%s'
              end
            end
          end
          return '%'..s
        end)
        message = string_format(message, table.unpack(args, 1, i))
      else
        message = string_format(message, ...)
      end
    end
  else
    local args = {message, ...}
    local l =  {}
    for i = 1, n + 1 do
      table.insert(l, format_t(args[i], true))
    end
    message = table.concat(l, ' ')
  end
  LOG_RECORD(logger, os_time(), level, message)
end

local function addLevel(levels, pattern, level)
  if level then
    -- cleanup duplicate patterns
    for i = #levels, 1, -1 do
      if levels[i].pattern == pattern then
        table.remove(levels, i)
      end
    end
    table.insert(levels, {
      pattern = pattern,
      level = level
    })
  end
end

local function getLevelByName(levels, name)
  local level
  if levels and name then
    for _, li in ipairs(levels) do
      if string_find(name, li.pattern) then
        level = li.level
      end
    end
  end
  return level
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

  local DEFAULT_LEVEL = LEVEL.WARN

  --- Creates a new logger with the specified level.
  -- @function Logger:new
  -- @tparam[opt] string name The module name
  -- @param[opt] level The log level
  -- @return a new logger
  -- @usage
  --local console = require('jls.lang.logger'):getClass():new()
  --console:info('Some usefull information message')
  function logger:initialize(name, level)
    self:setName(name)
    self:setLevel(level or DEFAULT_LEVEL)
  end

  function logger:setName(name)
    self.name = name
    self.sname = trunc(string.gsub(trim(name or ''), '%s+', '_'), NAME_LEN)
  end

  --- Returns the logger for the specified name.
  -- The returned logger inherits from this logger configuration.
  -- @tparam[opt] string name The module name
  -- @return a logger
  -- @usage
  --local console = require('jls.lang.logger'):get(...)
  --console:info('Some usefull information message')
  function logger:get(name)
    if type(name) == 'string' then
      if not self.loggerMap then
        self.loggerMap = {}
        -- allow loggers to be collected using weak values
        setmetatable(self.loggerMap, {__mode = 'v'})
      end
      local lgr = self.loggerMap[name]
      if lgr then
        return lgr
      end
      lgr = self:getClass():new(name, getLevelByName(self.levels, name))
      self.loggerMap[name] = lgr
      return lgr
    end
    return self
  end

  --- Returns the log level for this logger.
  -- @treturn number the log level for this logger.
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
  -- When the message is a string then additional arguments are formatted using `string.format` with the following additional specifiers.
  -- The specifier `t` or `T` stringifies the table argument.
  -- The specifier `l` formats a string or a table argument to its size.
  -- The specifier `x` or `X` formats a string argument to hexadecimal.
  -- @param level The log level.
  -- @param message The log message.
  function logger:log(level, message, ...)
    local l = parseLevel(level)
    if l >= self.level then
      log(self, l, message, ...)
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

  function logger:propagateLevel(level)
    if self.loggerMap then
      for _, lgr in pairs(self.loggerMap) do
        lgr:setLevel(level)
      end
    end
  end

  -- for compatibility, to remove
  function logger:cleanConfig()
    self.levels = nil
    self:propagateLevel(self.level)
  end

  --- Sets the specified logger level configuration.
  -- The configuration is a list of comma separated values of module name and associated level.
  -- The configuration is applied in the specified order on this logger and all its sub loggers.
  -- @tparam string config The log configuration.
  function logger:setConfig(config)
    local levels = {}
    if type(config) == 'string' then
      for part in string.gmatch(config, "[^,;\n\r]+") do
        local name, value = string.match(part, '^%s*([^=:]+)[=:]%s*(%w+)%s*$')
        if name then
          addLevel(levels, trim(name), levelFromString(value))
        else
          addLevel(levels, '', levelFromString(trim(part)))
        end
      end
    end
    if levels[1] then
      if self.loggerMap then
        for name, lgr in pairs(self.loggerMap) do
          lgr:setLevel(getLevelByName(levels, name) or DEFAULT_LEVEL)
        end
      end
      self.level = parseLevel(getLevelByName(levels, self.name or '') or DEFAULT_LEVEL)
      self.levels = levels
    else
      self.level = DEFAULT_LEVEL
      self.levels = nil
      self:propagateLevel(DEFAULT_LEVEL)
    end
  end

  -- for compatibility, to remove
  logger.applyConfig = logger.setConfig

  --- Returns the logger level configuration.
  -- @treturn string the configuration
  function logger:getConfig()
    if not self.levels then
      return nil
    end
    local configs = {}
    for _, li in ipairs(self.levels) do
      if li.pattern == '' then
        table.insert(configs, levelToString(li.level))
      else
        table.insert(configs, li.pattern..':'..levelToString(li.level))
      end
    end
    return table.concat(configs, ',')
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
Logger.parseLevel = parseLevel

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

-- for backward compatibility, the default instance propagates its level
function logger:setLevel(level)
  self.level = parseLevel(level)
  self:propagateLevel(self.level)
end

logger:setConfig(os.getenv('JLS_LOGGER_LEVEL'))
if logger:getLevel() >= LEVEL.INFO then
  logger:info('set log level to %s based on the JLS_LOGGER_LEVEL environment variable', levelToString(logger:getLevel()))
end

return logger