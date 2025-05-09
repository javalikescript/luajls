local lu = require('luaunit')

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local Logger = logger:getClass()

local LogFile = class.create(function(logFile)
  function logFile:initialize()
    self.messages = {}
  end
  function logFile:write(message)
    -- 2000-01-01T00:00:00 name level message
    -- 19 20 6 message
    local cm = string.gsub(string.sub(message, 20), '  +', ' ')
    cm = string.gsub(string.gsub(cm, '^%s+', ''), '%s+$', '')
    table.insert(self.messages, cm)
  end
  function logFile:flush()
  end
  function logFile:getMessagesAndClean()
    local messages = self.messages
    self.messages = {}
    return messages
  end
end)

local logFile = LogFile:new()

local savedLogFile = Logger.getLogFile()
local savedLogLevel = logger:getLevel()

local methodNameByLevel = {
  ERROR = 'error',
  WARN = 'warn',
  INFO = 'info',
  CONFIG = 'config',
  FINE = 'fine',
  FINER = 'finer',
  FINEST = 'finest',
  DEBUG = 'debug',
}

Tests = {}

function Tests:setUp()
  logFile:getMessagesAndClean()
  Logger.setLogFile(logFile)
end

function Tests:tearDown()
  Logger.setLogFile(savedLogFile)
  logger:setLevel(savedLogLevel)
end

function Tests:test_string()
  logger:setLevel(logger.INFO)
  logger:fine('nothing')
  logger:info('simple text')
  lu.assertEquals(logFile:getMessagesAndClean(), {'INFO simple text'})
  logger:info('simple %s text')
  lu.assertEquals(logFile:getMessagesAndClean(), {'INFO simple %s text'})
end

function Tests:test_format()
  logger:setLevel(logger.INFO)
  logger:fine('nothing')
  logger:info('simple %s text', 'formatted')
  lu.assertEquals(logFile:getMessagesAndClean(), {'INFO simple formatted text'})
  logger:info('simple %s text', nil)
  lu.assertEquals(logFile:getMessagesAndClean(), {'INFO simple nil text'})
  logger:info('simple %x hex', nil)
  lu.assertEquals(logFile:getMessagesAndClean(), {'INFO simple nil hex'})
  logger:info('simple %x %X hex', 10, 10)
  lu.assertEquals(logFile:getMessagesAndClean(), {'INFO simple a A hex'})
  logger:info('simple %x %X hex', 'Nn\n', 'Nn\n')
  lu.assertEquals(logFile:getMessagesAndClean(), {'INFO simple 4e6e0a 4E6E0A hex'})
  logger:info('simple %t table', nil)
  lu.assertEquals(logFile:getMessagesAndClean(), {'INFO simple nil table'})
  logger:info('simple %t table', 'a')
  lu.assertEquals(logFile:getMessagesAndClean(), {'INFO simple "a" table'})
  logger:info('simple %t table', {a=1})
  lu.assertEquals(logFile:getMessagesAndClean(), {'INFO simple {a=1,} table'})
  logger:info('simple %l length', nil)
  lu.assertEquals(logFile:getMessagesAndClean(), {'INFO simple nil length'})
  logger:info('simple %l length', 'a')
  lu.assertEquals(logFile:getMessagesAndClean(), {'INFO simple 1 length'})
  logger:info('simple %l length', {1, 2, 3})
  lu.assertEquals(logFile:getMessagesAndClean(), {'INFO simple 3 length'})
  logger:info('simple %l length', {a=1, b=2, c=3})
  lu.assertEquals(logFile:getMessagesAndClean(), {'INFO simple 3 length'})
end

function Tests:test_log()
  logger:setLevel(logger.INFO)
  logger:log('info', 'simple text')
  lu.assertEquals(logFile:getMessagesAndClean(), {'INFO simple text'})
  logger:log('fine', 'simple text')
  lu.assertEquals(logFile:getMessagesAndClean(), {})
end

function Tests:test_setLevel()
  logger:setLevel(logger.INFO)
  lu.assertEquals(logger:getLevel(), logger.INFO)
  logger:setLevel('ERROR')
  lu.assertEquals(logger:getLevel(), logger.ERROR)
  logger:setLevel('fine')
  lu.assertEquals(logger:getLevel(), logger.FINE)
end

function Tests:test_levels()
  for levelName, methodName in pairs(methodNameByLevel) do
    local level = Logger.levelFromString(levelName)
    logger:setLevel(level)
    lu.assertEquals(logger:getLevel(), level)
    lu.assertTrue(logger:isLoggable(level))
    logger[methodName](logger, 'text')
    lu.assertEquals(logFile:getMessagesAndClean(), {levelName..' text'})
  end
end

function Tests:test_setConfig()
  local l_a, l_b, l_c
  local function reset(a, b, c)
    l_a = Logger:new(a)
    l_b = l_a:get(b or 'a.b')
    l_c = l_a:get(c or 'a.c')
  end
  local function set(a, b, c)
    l_a:setLevel(a or Logger.LEVEL.WARN)
    l_b:setLevel(b or Logger.LEVEL.WARN)
    l_c:setLevel(c or Logger.LEVEL.WARN)
  end
  local function check(a, b, c)
    lu.assertEquals(l_a:getLevel(), a or Logger.LEVEL.WARN)
    lu.assertEquals(l_b:getLevel(), b or Logger.LEVEL.WARN)
    lu.assertEquals(l_c:getLevel(), c or Logger.LEVEL.WARN)
  end

  reset()
  check()

  set(Logger.LEVEL.FINER, Logger.LEVEL.FINE, Logger.LEVEL.INFO)
  check(Logger.LEVEL.FINER, Logger.LEVEL.FINE, Logger.LEVEL.INFO)

  reset()
  check()

  l_a:setConfig()
  check()
  reset()

  l_a:setConfig('fine')
  check(Logger.LEVEL.FINE, Logger.LEVEL.FINE, Logger.LEVEL.FINE)
  reset()

  l_a:setConfig('a=fine')
  check(nil, Logger.LEVEL.FINE, Logger.LEVEL.FINE)
  reset()

  l_a:setConfig('a.c=fine')
  check(nil, nil, Logger.LEVEL.FINE)
  reset()

  l_a:setConfig('info;a.b=fine')
  check(Logger.LEVEL.INFO, Logger.LEVEL.FINE, Logger.LEVEL.INFO)
  reset()

  l_a:setConfig(' info ; a.b =  fine ')
  check(Logger.LEVEL.INFO, Logger.LEVEL.FINE, Logger.LEVEL.INFO)
  reset()
end

function Tests:test_getConfig()
  local l = Logger:new()
  lu.assertNil(l:getConfig())
  l:setConfig('info;a.b=fine')
  lu.assertEquals(l:getConfig(), 'INFO,a.b:FINE')
end

os.exit(lu.LuaUnit.run())
