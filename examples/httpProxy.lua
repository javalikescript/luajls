local logger = require('jls.lang.logger')
local event = require('jls.lang.event')
local HttpServer = require('jls.net.http.HttpServer')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local HttpExchange = require('jls.net.http.HttpExchange')
local ProxyHttpHandler = require('jls.net.http.handler.ProxyHttpHandler')
local tables = require('jls.util.tables')
local system = require('jls.lang.system')

local ProxyHandler = require('jls.lang.class').create(ProxyHttpHandler, function(proxyHandler, super)

  local function readAllPatterns(filename)
    local t = {}
    local file = filename and io.open(filename)
    if file then
      for l in file:lines('l') do
        if l ~= '' then
          local line = l
          --local isPattern = string.match(line, '[%*%+]') ~= nil
          if not string.match(line, '^%^') then
            line = string.gsub(line, '([%^%$%(%)%%%.%[%]%-%?])', '%%%1')
            line = string.gsub(line, '%*', '.*')
            line = string.gsub(line, '%+', '[^%.]+')
            line = '^'..line..'$'
            logger:finer('add pattern: "%s"', line)
          end
          table.insert(t, line)
        end
      end
      file:close()
    end
    return t
  end

  local function isValid(value)
    return type(value) == 'string' and value ~= '' and value ~= '-'
  end

  local function readAllKeys(filename)
    local t = {}
    local file = isValid(filename) and io.open(filename)
    if file then
      for line in file:lines('l') do
        if line ~= '' then
          t[line] = true
        end
      end
      file:close()
    end
    return t
  end

  function proxyHandler:initialize(proxyConfig)
    super.initialize(self)
    if type(proxyConfig) ~= 'table' then
      proxyConfig = {}
    end
    self:configureForward(proxyConfig.allowConnect)
    self.acceptUnknown = proxyConfig.acceptUnknown == true
    self.unknownMap = readAllKeys(proxyConfig.unknownList)
    self:loadConfig(proxyConfig)
    self:save(proxyConfig)
  end

  function proxyHandler:loadConfig(proxyConfig)
    self.allowList = readAllPatterns(proxyConfig.allowList)
    self.denyList = readAllPatterns(proxyConfig.denyList)
  end

  function proxyHandler:save(proxyConfig)
    if isValid(proxyConfig.unknownList) then
      local hosts = tables.keys(self.unknownMap)
      table.sort(hosts)
      local file = io.open(proxyConfig.unknownList, 'w')
      for _, host in ipairs(hosts) do
        file:write(host, '\n')
      end
      file:close()
    end
    if proxyConfig.log.enabled then
      if not self.logs then
        self.logs = {}
      end
      local file = io.open(proxyConfig.log.file, 'a')
      for _, log in ipairs(self.logs) do
        file:write(log, '\n')
      end
      file:close()
      self.logs = {}
    end
  end

  local function matchAny(list, value)
    for _, pattern in ipairs(list) do
      if string.match(value, pattern) then
        return true
      end
    end
    return false
  end

  function proxyHandler:log(exchange, status, target)
    local userAgent = exchange:getRequest():getHeader(HTTP_CONST.HEADER_USER_AGENT)
    local remoteName = exchange.client and exchange.client:getRemoteName()
    if self.logs then
      local log = os.date('%Y-%m-%dT%H:%M:%S', os.time())..','..status..','..tostring(target)..','..tostring(remoteName)..',"'..tostring(userAgent)..'"'
      table.insert(self.logs, log)
    else
      logger:info('%s,%s,%s,"%s"', status, target, remoteName, userAgent)
    end
  end

  function proxyHandler:acceptMethod(exchange, method)
    if super.acceptMethod(self, exchange, method) then
      return true
    end
    self:log(exchange, 'method', method)
    return false
  end

  function proxyHandler:acceptHost(exchange, host)
    if matchAny(self.allowList, host) then
      logger:fine('host "%s" is allowed', host)
      return true
    end
    local isDenied = matchAny(self.denyList, host)
    if isDenied then
      HttpExchange.forbidden(exchange)
      self:log(exchange, 'denied', host)
      return false
    end
    if self.acceptUnknown then
      self.unknownMap[host] = true
      return true
    end
    HttpExchange.forbidden(exchange)
    self:log(exchange, 'forbidden', host)
    return false
  end

end)

local CONFIG_SCHEMA = {
  title = 'HTTP proxy',
  type = 'object',
  additionalProperties = false,
  properties = {
    config = {
      title = 'The configuration file',
      type = 'string',
      default = 'httpProxy.json'
    },
    server = {
      type = 'object',
      additionalProperties = false,
      properties = {
        address = {
          title = 'The binding address',
          type = 'string',
          default = '::'
        },
        port = {
          type = 'integer',
          default = 8080,
          minimum = 0,
          maximum = 65535,
        },
      },
    },
    heartbeat = {
      type = 'number',
      default = 15,
      multipleOf = 0.1,
      minimum = 0.5,
      maximum = 3600,
    },
    proxy = {
      type = 'object',
      additionalProperties = false,
      properties = {
        allowConnect = {
          type = 'boolean',
          default = true
        },
        acceptUnknown = {
          type = 'boolean',
          default = true
        },
        allowList = {
          title = 'A file with the list of allowed hosts',
          type = 'string',
          default = 'proxy_allow_list.txt'
        },
        denyList = {
          title = 'A file with the list of denied hosts',
          type = 'string',
          default = 'proxy_deny_list.txt'
        },
        unknownList = {
          title = 'A file that will list the unknown hosts',
          type = 'string',
          default = 'proxy_unknown_list.txt'
        },
        log = {
          type = 'object',
          additionalProperties = false,
          properties = {
            enabled = {
              type = 'boolean',
              default = false
            },
            file = {
              title = 'The log file',
              type = 'string',
              default = 'proxy.log'
            },
          },
        },
      },
    },
  },
}

local config = tables.createArgumentTable(system.getArguments(), {
  configPath = 'config',
  emptyPath = 'config',
  helpPath = 'help',
  logPath = 'log-level',
  aliases = {
    h = 'help',
    b = 'server.address',
    hb = 'heartbeat',
    p = 'server.port',
    pl = 'proxy.log.enabled',
    ll = 'log-level',
  },
  schema = CONFIG_SCHEMA
});

local httpServer = HttpServer:new()
httpServer:bind(config.server.address, config.server.port):next(function()
  logger:info('Proxy server bound to "%s" on port %s', config.server.address, config.server.port)
  local proxyHandler = ProxyHandler:new(config.proxy)
  httpServer:createContext('(.*)', proxyHandler)
  event:setInterval(function()
    logger:finer('Proxy saved')
    proxyHandler:save(config.proxy)
  end, math.floor(config.heartbeat * 1000))
end):catch(function(err) -- could failed if address is in use or hostname cannot be resolved
  print('Cannot bind proxy server, '..tostring(err))
  os.exit(1)
end)

event:loop()
logger:info('Proxy server closed')
