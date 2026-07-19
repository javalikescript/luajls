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
local RestHttpHandler = require('jls.net.http.handler.RestHttpHandler')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local Http1 = require('jls.net.http.Http1')
local Url = require('jls.net.Url')
local File = require('jls.io.File')
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
        return '/ReW/static/not-found'
      end
      return '/ReW/'..b..'/'..opts..url:getFile()
    end
  elseif string.find(href, '^/') then
    if string.find(href, '^//') and base then
      local d = base64:decodeSafe(base)
      local p = string.match(d, '^([^:]+:)')
      if p then
        return encodeHref(p..href, base, opts)
      end
    else
      return '/ReW/'..base..'/'..opts..href
    end
  end
  return href
end

local RewriteProxyHandler = class.create(ProxyHttpHandler, function(handler, super)

  function handler:initialize()
    super.initialize(self)
    self.exchanges = {}
  end

  function handler:getTargetUrl(exchange)
    local e, o, p = exchange:getRequestArguments()
    local q = string.match(exchange:getRequest():getTarget(), '^[^%?]*(%?.+)$')
    local b = base64:decodeSafe(e)
    if b then
      logger:fine('rewrite URL is "%s" "%s" "%s" "%s"', b, o, p, q)
      exchange:setAttribute('base-url', b)
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
    local _, opts = exchange:getRequestArguments()
    if string.find(opts, 'u', 1, true) then
      request:setHeader('user-agent', self.userAgent)
    end
    request:setHeader('referer')
    exchange:setAttribute('client-request', request)
  end

  local function transformCss(data, base, opts)
    return (string.gsub(data, 'url%(%s*([^%)]+)%)', function(url)
      local c, u = string.match(url, '^%s*([\'"])([^\'"]+)[\'"]%s*$')
      if c then
        return 'url('..c..encodeHref(u, base, opts)..c..')'
      end
      return 'url('..encodeHref(url, base, opts)..')'
    end))
  end

  local function findTag(data, name, before)
    local namePattern = string.gsub(name, '%a', function(a)
      return '['..string.lower(a)..string.upper(a)..']'
    end)
    local s, e = string.find(data, '<'..namePattern..'>')
    if not s then
      s, e = string.find(data, '<'..namePattern..'%s[^>]*>')
    end
    if s then
      if before then
        return s - 1
      end
      return e
    end
  end

  local function processXmlAttributes(a, r)
    local function f(n, v, s)
      local w = r(string.lower(n), v)
      if w then
        return n..'='..s..w..s
      end
      return ''
    end
    local b = string.gsub(a, '(%w+)%s*=%s*"([^"]+)(")', f)
    return string.gsub(b, "(%w+)%s*=%s*'([^']+)(')", f)
  end

  local function transformHtml(data, base, opts)
    local function replStyle(n, v)
      if n == 'style' then
        return transformCss(v, base, opts)
      end
      if n == 'nonce' then
        return nil
      end
      return v
    end
    local function urlToQuery(n, v)
      if n == 'href' or n == 'src' or n == 'action' then
        return encodeHref(v, base, opts)
      elseif n == 'srcset' then
        return string.gsub(v, '[^,]+', function(w)
          return encodeHref(string.gsub(w, '^%s+', ''), base, opts)
        end)
      end
      return replStyle(n, v)
    end
    local d = string.gsub(data, '<%s*(%w+)([^>]*)>', function(tag, atts)
      local m = string.gsub(atts, '%s+$', '')
      local s = ''
      if string.sub(m, #m) == '/' then
        m = string.sub(m, 1, -2)
        s = '/'
      end
      local t = string.lower(tag)
      if t == 'script' and string.find(opts, 's', 1, true) then
        m = ' type="text/plain"'
      elseif t == 'a' or t == 'link' or t == 'area' or t == 'base' or t == 'img' or t == 'script' or t == 'iframe' then
        m = processXmlAttributes(m, urlToQuery)
      else
        m = processXmlAttributes(m, replStyle)
      end
      return '<'..tag..m..s..'>'
    end)
    local i = findTag(d, 'head') or findTag(d, 'html') or findTag(d, 'script', true) or findTag(d, 'body')
    if i then
      d = string.sub(d, 1, i)..'<script src="/ReW/static/observe.js"></script>'..string.sub(d, i + 1)
    end
    return d
  end

  function handler:adaptResponseStreamHandler(exchange, sh)
    local response = exchange:getResponse()
    local resRawHeaders = response:getRawHeaders()
    -- remove unsupported headers
    response:setHeader('content-security-policy')
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
      -- TODO handle cookies prefixed with '__'
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
    response:setHeader('transfer-encoding')
    response:setContentLength(nil)
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
        if self.record and self.record > 0 then
          local req = exchange:getAttribute('client-request') or exchange:getRequest()
          local bu = exchange:getAttribute('base-url')
          table.insert(self.exchanges, {
            b = bu,
            req = {l = req:formatLine(), h = req:getRawHeaders()},
            res = {l = response:formatLine(), h = resRawHeaders, b = data}
          })
          local n = #self.exchanges
          if n > self.record then
            self.exchanges = table.move(self.exchanges, n - self.record + 1, n, 1, {})
          end
        end
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

local RESOURCE_MAP = {
  ['observe.js'] = File:new('examples/httpProxy.js'):readAll(),
  ['exchanges.html'] = File:new('examples/httpProxy.html'):readAll(),
}

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
    secure = {
      type = 'object',
      additionalProperties = false,
      properties = {
        enabled = {
          title = 'Enable HTTPS',
          type = 'boolean',
          default = false
        },
        port = {
          type = 'integer',
          default = 8443,
          minimum = 0,
          maximum = 65535,
        },
        commonName = {
          title = "The server common name",
          type = "string",
          default = "localhost"
        },
        certificate = {
          title = "The certificate file",
          type = "string",
          default = "cer.pem"
        },
        key = {
          title = "The key file",
          type = "string",
          default = "key.pem"
        }
      }
    },
    reverseUrl = {
      title = 'The URL to use for the reverse proxy',
      type = 'string',
      pattern = '^https?://.+$',
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
        },
        record = {
          title = 'Max number of exchanges to record',
          type = 'number',
          default = 0,
        },
        ['user-agent'] = {
          title = 'The user agent to use when rewriting',
          type = 'string'
        },
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
    s = 'secure.enabled',
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
            local flags = exchange:getRequest():getSearchParam('flags')
            logger:info('URL is "%s", flags are "%s"', url, flags)
            HttpExchange.redirect(exchange, encodeHref(url, nil, flags or 'a'))
            return false
          end
          local response = exchange:getResponse()
          local sampleUrl = 'http://localhost:8000'
          local sampleFlags = 'a'
          response:setBody(string.format([[<!DOCTYPE html>
  <html>
    <body>
      <p>Please provide an URL in the query!</p>
      <p>As in <a href="%s">this example</a></p>
      <br/>
      <p>List the <a href="/ReW/static/exchanges.html">HTTP exchanges</a></p>
      <br/>
      <input id="url" type="text" placeholder="URL" value="]]..sampleUrl..[["/>
      <input id="flags" type="text" placeholder="flags" value="]]..sampleFlags..[[" title="'s' to disable script, 'u' to override user agent"/>
      <button id="go">Go</button>
      <script>
      function asUrlParam(name) {
        return name + '=' + encodeURIComponent(document.getElementById(name).value);
      }
      document.getElementById('go').addEventListener('click', function() {
        window.location.href = '?' + asUrlParam('url') + '&' + asUrlParam('flags');
      });
      </script>
    </body>
  </html>
  ]], encodeHref(sampleUrl, nil, sampleFlags)))
        else
          HttpExchange.notFound(exchange)
        end
      end)

    local proxyHandler = RewriteProxyHandler:new()
    local userAgent = config.rewrite['user-agent']
    if userAgent == 'android-11' then
      proxyHandler.userAgent = 'Mozilla/5.0 (Linux; Android 11; Pixel 4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.210 Mobile Safari/537.36'
    elseif userAgent == 'lumia-650' then
      proxyHandler.userAgent = 'Mozilla/5.0 (Windows Phone 10.0; Android 6.0.1; Microsoft; Lumia 650) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/52.0.2743.116 Mobile Safari/537.36 Edge/15.15254'
    else
      proxyHandler.userAgent = userAgent
    end
    proxyHandler.record = config.rewrite.record
    httpServer:createContext('/ReW/(%w+)/(%w+)(.*)', proxyHandler)
    httpServer:createContext('/ReW/rest/(.+)', RestHttpHandler:new({
      ['clearExchanges?method=POST'] = function()
        proxyHandler.exchanges = {}
      end,
      exchanges = function()
        return proxyHandler.exchanges
      end
    }))
    httpServer:createContext('/ReW/static/not-found', function(exchange)
      HttpExchange.notFound(exchange)
    end)
    httpServer:createContext('/ReW/static/(.+)', function(exchange)
      local n = exchange:getRequestArguments()
      local c = RESOURCE_MAP[n]
      if c then
          local response = exchange:getResponse()
          response:setStatusCode(200, 'OK')
          response:setContentType(FileHttpHandler.guessContentType(n))
          response:setCacheControl(43200)
          response:setContentLength(#c)
          if exchange:getRequestMethod() == 'GET' then
            response:setBody(c)
          end
      else
        HttpExchange.notFound(exchange)
      end
    end)
  elseif config.reverseUrl then
    local proxyHandler = ProxyHttpHandler:new()
    proxyHandler:configureReverse(config.reverseUrl)
    httpServer:createContext('(.*)', proxyHandler)
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

if config.secure.enabled then
  local secure = require('jls.net.secure')
  local Date = require('jls.util.Date')

  local certFile = File:new(config.secure.certificate)
  local pkeyFile = File:new(config.secure.key)
  if not certFile:exists() or not pkeyFile:exists() then
    local cacert, pkey = secure.createCertificate({
      commonName = config.secure.commonName
    })
    local cacertPem  = cacert:export('pem')
    local pkeyPem  = pkey:export('pem')
    certFile:write(cacertPem)
    pkeyFile:write(pkeyPem)
    logger:info('Generate certificate %s and associated private key %s', certFile:getPath(), pkeyFile:getPath())
  else
    local cert = secure.readCertificate(certFile:readAll())
    local isValid, notbefore, notafter = cert:validat()
    local notafterDate = Date:new(notafter:get() * 1000)
    local notafterText = notafterDate:toISOString(true)
    logger:info('Using certificate %s valid until %s', certFile:getPath(), notafterText)
    if not isValid then
      logger:warn('The certificate is no more valid since %s', notafterText)
    end
  end

  local httpSecureServer = HttpServer.createSecure({
    certificate = certFile:getPath(),
    key = pkeyFile:getPath(),
    alpnProtocols = config.h2 and {'h2', 'http/1.1'} or nil,
  })
  httpSecureServer:bind(config['bind-address'], config.secure.port):next(function()
    logger:info('HTTPS bound to "%s" on port %d', config['bind-address'], config.secure.port)
    stopPromise:next(function()
      logger:info('Closing HTTP secure server')
      httpSecureServer:close()
    end)
  end, function(err)
    logger:warn('Cannot bind HTTP to "%s" on port %d due to %s', config['bind-address'], config.secure.port, err)
  end)
  httpSecureServer:setParent(httpServer)
end

stopPromise:next(signal('?!sigint', function() stopCallback() end))

event:loop()
logger:info('Proxy server closed')
