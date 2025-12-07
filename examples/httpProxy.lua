local class = require('jls.lang.class')
local logger = require('jls.lang.logger'):get('httpProxy')
local event = require('jls.lang.event')
local signal = require('jls.lang.signal')
local system = require('jls.lang.system')
local Promise = require('jls.lang.Promise')
local HttpServer = require('jls.net.http.HttpServer')
local HttpMessage = require('jls.net.http.HttpMessage')
local HttpHeaders = require('jls.net.http.HttpHeaders')
local HttpExchange = require('jls.net.http.HttpExchange')
local ProxyHttpHandler = require('jls.net.http.handler.ProxyHttpHandler')
local Http1 = require('jls.net.http.Http1')
local Url = require('jls.net.Url')
local StreamHandler = require('jls.io.StreamHandler')
local BufferedStreamHandler = require('jls.io.streams.BufferedStreamHandler')
local tables = require('jls.util.tables')
local Codec = require('jls.util.Codec')
local strings = require('jls.util.strings')
local List = require('jls.util.List')

local base64 = Codec.getInstance('base64', 'safe', false)

local ProxyHandler = class.create(ProxyHttpHandler, function(handler, super)

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

  function handler:initialize(proxyConfig)
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

  function handler:loadConfig(proxyConfig)
    self.allowList = readAllPatterns(proxyConfig.allowList)
    self.denyList = readAllPatterns(proxyConfig.denyList)
  end

  function handler:save(proxyConfig)
    if isValid(proxyConfig.unknownList) then
      local hosts = tables.keys(self.unknownMap)
      table.sort(hosts)
      local file = assert(io.open(proxyConfig.unknownList, 'w'))
      for _, host in ipairs(hosts) do
        file:write(host, '\n')
      end
      file:close()
    end
    if proxyConfig.log.enabled then
      if not self.logs then
        self.logs = {}
      end
      local file = assert(io.open(proxyConfig.log.file, 'a'))
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

  function handler:log(exchange, status, target)
    local userAgent = exchange:getRequest():getHeader(HttpMessage.CONST.HEADER_USER_AGENT)
    local remoteName = exchange.client and exchange.client:getRemoteName()
    if self.logs then
      local log = os.date('%Y-%m-%dT%H:%M:%S', os.time())..','..status..','..tostring(target)..','..tostring(remoteName)..',"'..tostring(userAgent)..'"'
      table.insert(self.logs, log)
    else
      logger:info('%s,%s,%s,"%s"', status, target, remoteName, userAgent)
    end
  end

  function handler:acceptMethod(exchange, method)
    if super.acceptMethod(self, exchange, method) then
      return true
    end
    self:log(exchange, 'method', method)
    return false
  end

  function handler:acceptHost(exchange, host)
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

local function formatBaseUrl(url)
  return url:getProtocol()..'://'..url:getAuthority()
end

local function encodeHref(href, base, opts)
  local url = Url.fromString(href)
  if url then
    if url:getProtocol() == 'https' or url:getProtocol() == 'http' then
      local b = base64:encode(formatBaseUrl(url))
      if b ~= base and string.find(opts, 'o', 1, true) then
        return '/not-found'
      end
      return '/r/'..b..'/'..opts..url:getFile()
    end
  elseif string.find(href, '^/') then
    return '/r/'..base..'/'..opts..href
  end
  return href
end

local RewriteProxyHandler = class.create(ProxyHttpHandler, function(handler, super)

  function handler:initialize()
    super.initialize(self)
  end

  function handler:getTargetUrl(exchange)
    local e, o, p = exchange:getRequestArguments()
    local q = string.match(exchange:getRequest():getTarget(), '^[^%?]*(%?.+)$')
    local b = base64:decodeSafe(e)
    if b then
      logger:fine('rewrite url is "%s" "%s" "%s" "%s"', b, o, p, q)
      return Url.fromString(q and b..p..q or b..p)
    end
  end

  local ACCEPTED_ENCODINGS = List.asSet(strings.split('*,identity,deflate,gzip', ','))

  function handler:prepareRequest(exchange, request)
    local l = {}
    local ae = exchange:getRequest():getHeaderValues('accept-encoding')
    for _, e in ipairs(ae) do
      local n = string.lower(HttpHeaders.parseHeaderValue(e))
      if ACCEPTED_ENCODINGS[n] then
        table.insert(l, e)
      end
    end
    request:setHeaderValues('accept-encoding', #l > 0 and l or {'identity'})
  end

  local function transformCss(data, base, opts)
    return (string.gsub(data, 'url%(%s*([^%)]+)%)', function(url)
      return 'url('..encodeHref(url, base, opts)..')'
    end))
  end

  local function transformHtml(data, base, opts)
    local function urlToQuery(n, v, s)
      local m = string.lower(n)
      if m == 'href' or m == 'src' then
        v = encodeHref(v, base, opts)
      end
      return n..'='..s..v..s
    end
    return (string.gsub(data, '<%s*(%w+)([^>]*)>', function(tag, atts)
      local m = string.gsub(atts, '%s+$', '')
      local s = ''
      if string.sub(m, #m) == '/' then
        m = string.sub(m, 1, -2)
        s = '/'
      end
      local t = string.lower(tag)
      if t == 'script' and string.find(opts, 's', 1, true) then
        m = ' type="text/plain"'
      elseif t == 'a' or t == 'img' or t == 'link' or t == 'script' then
        m = string.gsub(m, '(%w+)%s*=%s*"([^"]+)(")', urlToQuery)
        m = string.gsub(m, "(%w+)%s*=%s*'([^']+)(')", urlToQuery)
      end
      return '<'..tag..m..s..'>'
    end))
  end

  function handler:adaptResponseStreamHandler(exchange, sh)
    local response = exchange:getResponse()
    -- remove unsupported headers
    response:setHeader('content-security-policy-report-only')
    response:setHeader('report-to')
    response:setHeader('nel')
    response:setHeader('link')
    local base, opts = exchange:getRequestArguments()
    local location = response:getHeader('location')
    if location then
      response:setHeader('location', encodeHref(location, base, opts))
    end
    local setCookies = response:getHeaderValues('set-cookie')
    for i, v in ipairs(setCookies) do
      setCookies[i] = string.gsub(v, '; *[Dd]omain *=[^;]+', '')
    end
    response:setHeader('set-cookie', setCookies)
    local transform
    local contentType = response:getContentType()
    if contentType == 'text/html' then
      transform = transformHtml
    elseif contentType == 'text/css' then
      transform = transformCss
    end
    if not transform then
      return sh
    end
    response:setContentLength()
    response:setHeader('transfer-encoding')
    return BufferedStreamHandler:new(StreamHandler:new(function(err, data)
      if err then
        return sh:onError(err)
      end
      if data then
        local d = transform(data, base, opts)
        logger:fine('transformed %s length %l -> %l', contentType, data, d)
        logger:finest('transformed to %s', d)
        local l = #d
        response:setContentLength(l)
        if l > Http1.BODY_BLOCK_SIZE then
          local pt = {}
          for value in strings.parts(d, Http1.BODY_BLOCK_SIZE) do
            local p = sh:onData(value)
            if p ~= nil then
              table.insert(pt, p)
            end
          end
          return Promise.all(pt)
        elseif l > 0 then
          return sh:onData(d)
        end
      else
        return sh:onData()
      end
    end)), true
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
    rewrite = {
      type = 'object',
      additionalProperties = false,
      properties = {
        enabled = {
          type = 'boolean',
          default = false
        }
      }
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
    r = 'rewrite.enabled',
  },
  schema = CONFIG_SCHEMA
});

local stopPromise, stopCallback = Promise.withCallback()

local httpServer = HttpServer:new()
httpServer:bind(config.server.address, config.server.port):next(function()
  logger:info('Proxy server bound to "%s" on port %s', config.server.address, config.server.port)
  stopPromise:next(function()
    logger:info('Closing HTTP server')
    httpServer:close()
  end)
  if config.rewrite and config.rewrite.enabled then
      logger:info('\n%s%s%s', string.rep('-', 60), string.rep('\n', 10), string.rep('-', 60))
      httpServer:createContext('.*', function(exchange)
        local path = exchange:getRequestPath()
        if path == '' or path == '/' then
          local url = exchange:getRequest():getSearchParam('url')
          if url then
            url = Url.decodePercent(url)
            logger:info('url is "%s"', url)
            HttpExchange.redirect(exchange, encodeHref(url, nil, 'a'))
            return false
          end
          local response = exchange:getResponse()
          response:setBody(string.format([[<!DOCTYPE html>
  <html>
    <body>
      <p>Please provide an URL in the query!</p>
      <p>As in <a href="%s">this example</a></p>
    </body>
  </html>
  ]], encodeHref('http://localhost:8000', nil, 'a')))
        else
          HttpExchange.notFound(exchange)
        end
      end)

    local proxyHandler = RewriteProxyHandler:new()
    httpServer:createContext('/r/(%w+)/(%w+)(.*)', proxyHandler)
  else
    local proxyHandler = ProxyHandler:new(config.proxy)
    httpServer:createContext('(.*)', proxyHandler)
    local i = event:setInterval(function()
      logger:finer('Proxy saved')
      proxyHandler:save(config.proxy)
    end, math.floor(config.heartbeat * 1000))
    stopPromise:next(function()
      logger:info('Closing interval')
      event:clearInterval(i)
    end)
  end
end):catch(function(err) -- could failed if address is in use or hostname cannot be resolved
  print('Cannot bind proxy server, '..tostring(err))
  os.exit(1)
end)

stopPromise:next(signal('?!sigint', function() stopCallback() end))

event:loop()
logger:info('Proxy server closed')
