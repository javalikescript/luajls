local lu = require('luaunit')

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local Logger = logger:getClass()

local logPattern = '^[%d%-T:]+ (.*)'..Logger.EOL..'$'

local LogFile = class.create(function(logFile)
  function logFile:initialize()
    self.messages = {}
  end
  function logFile:write(message)
    table.insert(self.messages, (string.match(message, logPattern)))
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
  for levelName, methodName in pairs(methodNameByLevel) do
    local level = Logger.levelFromString(levelName) + 1
    logger:setLevel(level + 1)
    lu.assertFalse(logger:isLoggable(level))
    logger[methodName](logger, 'text')
    lu.assertEquals(logFile:getMessagesAndClean(), {})
  end
end

os.exit(lu.LuaUnit.run())
