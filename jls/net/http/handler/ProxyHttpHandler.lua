--- Provide a simple HTTP handler that proxies requests.
-- See https://tools.ietf.org/html/rfc7230 and https://tools.ietf.org/html/rfc7231
-- @module jls.net.http.handler.ProxyHttpHandler
-- @pragma nostrip

local logger = require('jls.lang.logger'):get(...)
local HttpClient = require('jls.net.http.HttpClient')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local HttpExchange = require('jls.net.http.HttpExchange')
local HttpHeaders = require('jls.net.http.HttpHeaders')
local DelayedStreamHandler = require('jls.io.streams.DelayedStreamHandler')
local Promise = require('jls.lang.Promise')
local Url = require('jls.net.Url')
local TcpSocket = require('jls.net.TcpSocket')

--- A ProxyHttpHandler class.
-- @type ProxyHttpHandler
return require('jls.lang.class').create('jls.net.http.HttpHandler', function(proxyHttpHandler)

  --- Creates a proxy @{HttpHandler}.
  function proxyHttpHandler:initialize()
    self.allowConnect = false
    self.allowConnectAnyPort = false
    self.isReverse = false
    self.baseUrlIndex = 1
    self.pendings = {}
  end

  --- Configures this proxy to forward requests.
  -- This is the default proxy mode allowing monitoring and filtering.
  -- @tparam[opt] boolean allowConnect true to allow connect method.
  -- @treturn ProxyHttpHandler this proxy for chaining.
  function proxyHttpHandler:configureForward(allowConnect)
    self.isReverse = false
    self.allowConnect = allowConnect == true
    return self
  end

  function proxyHttpHandler:configureAllowConnect(allowConnect)
    self.allowConnect = allowConnect == true
    return self
  end

  --- Configures this proxy as reverse proxy.
  -- This mode allows to serve distinct services on the same server or
  -- serve distinct servers on the same endpoint.
  -- @tparam[opt] string baseUrl a base URL to forward requests to.
  -- @treturn ProxyHttpHandler this proxy for chaining.
  function proxyHttpHandler:configureReverse(baseUrl)
    self.isReverse = true
    self:setBaseUrl(baseUrl)
    return self
  end

  function proxyHttpHandler:addBaseUrl(baseUrl)
    if not self.baseUrls then
      self.baseUrls = {}
    end
    table.insert(self.baseUrls, (string.gsub(baseUrl, '/+$', '')))
    return self
  end

  function proxyHttpHandler:setBaseUrl(baseUrl)
    self.baseUrls = nil
    if type(baseUrl) == 'string' then
      self:addBaseUrl(baseUrl)
    elseif type(baseUrl) == 'table' and #baseUrl > 0 then
      for _, u in ipairs(baseUrl) do
        self:addBaseUrl(u)
      end
    end
    return self
  end

  local ALLOWED_METHODS = {
    HTTP_CONST.METHOD_GET,
    HTTP_CONST.METHOD_HEAD,
    HTTP_CONST.METHOD_POST,
    HTTP_CONST.METHOD_PUT,
    HTTP_CONST.METHOD_DELETE,
    HTTP_CONST.METHOD_OPTIONS,
  }

  function proxyHttpHandler:acceptMethod(exchange, method)
    return HttpExchange.methodAllowed(exchange, ALLOWED_METHODS)
  end

  function proxyHttpHandler:acceptHost(exchange, host)
    logger:info('Proxy host "%s"', host)
    if host == nil then
      HttpExchange.forbidden(exchange)
      return false
    end
    return true
  end

  function proxyHttpHandler:getBaseUrl(exchange)
    if self.baseUrls then
      self.baseUrlIndex = (self.baseUrlIndex % #self.baseUrls) + 1
      local baseUrl = self.baseUrls[self.baseUrlIndex]
      return baseUrl
    end
    local hostport = exchange:getRequest():getHeader(HTTP_CONST.HEADER_HOST)
    if hostport and hostport ~= '' then
      return 'http://'..hostport
    end
    return nil
  end

  function proxyHttpHandler:getTargetUrl(exchange)
    if self.isReverse then
      local baseUrl = self:getBaseUrl(exchange)
      if baseUrl then
        local path = exchange:getRequestPath()
        if path then
          return Url.fromString(baseUrl..string.gsub(path, '^/*', '/'))
        end
      end
    else
      local target = exchange:getRequest():getTarget()
      local targetUrl = Url.fromString(target)
      if targetUrl and targetUrl:getProtocol() ~= 'http' then
        return nil
      end
      return targetUrl
    end
    return nil
  end

  local function connectStream(fromClient, toClient, callback)
    fromClient:readStart(function(err, data)
      if err then
        logger:fine('tunnel error "%s"', err)
      elseif data then
        toClient:write(data)
        return
      end
      callback()
    end)
  end

  local function returnFalse()
    return false
  end

  function proxyHttpHandler:handleConnect(exchange)
    local hostport = exchange:getRequest():getTarget()
    local host, port = string.match(hostport, '^(.+):(%d+)$')
    if not host then
      HttpExchange.badRequest(exchange)
      return
    end
    port = tonumber(port) or 443
    if port ~= 443 and not self.allowConnectAnyPort then
      HttpExchange.forbidden(exchange)
      return
    end
    if not self:acceptHost(exchange, host) then
      return
    end
    logger:finer('connecting to "%s"', hostport)
    local client
    return Promise:new(function(resolve, reject)
      local targetClient = TcpSocket:new()
      targetClient:connect(host, port):next(function()
        logger:fine('connected to "%s"', hostport)
        exchange.applyKeepAlive = returnFalse
        function exchange.close()
          client = exchange.client
          exchange.client = nil
          self.pendings[client] = targetClient
          HttpExchange.prototype.close(exchange)
          local onStreamClosed = function()
            if self.pendings[client] then
              logger:fine('connect to "%s" closed', hostport)
              self.pendings[client] = nil
              client:close()
              targetClient:close()
            end
          end
          connectStream(client, targetClient, onStreamClosed)
          connectStream(targetClient, client, onStreamClosed)
        end
        HttpExchange.ok(exchange)
        resolve()
      end, function(err)
        logger:fine('connect error "%s"', err)
        if client then
          client:close()
        end
        reject('Cannot connect')
      end)
    end)
  end

  function proxyHttpHandler:handle(exchange)
    local request = exchange:getRequest()
    local response = exchange:getResponse()
    local method = request:getMethod()
    if method == HTTP_CONST.METHOD_CONNECT and self.allowConnect then
      return self:handleConnect(exchange)
    end
    if not self:acceptMethod(exchange, method) then
      return
    end
    local targetUrl = self:getTargetUrl(exchange)
    if not targetUrl then
      HttpExchange.badRequest(exchange)
      return
    end
    if not self:acceptHost(exchange, targetUrl:getHost()) then
      return
    end
    logger:fine('forward to "%s"', targetUrl)
    -- See https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Forwarded
    local headers = HttpHeaders:new()
    headers:addHeadersTable(request:getHeadersTable())
    local hostport = request:getHeader(HTTP_CONST.HEADER_HOST)
    if hostport then
      local forwarded = 'host='..hostport..';proto='..targetUrl:getProtocol()
      local by = exchange:clientAsString()
      if by then
        forwarded = 'by='..by..';for='..by..';'..forwarded
      end
      headers:setHeader('Forwarded', forwarded)
      headers:setHeader(HTTP_CONST.HEADER_HOST, targetUrl:getHost())
    end
    local client = HttpClient:new({
      url = targetUrl:toString(),
      method = method,
      headers = headers:getHeadersTable()
    })
    -- buffer incoming request body prior client connection
    request:setBodyStreamHandler(DelayedStreamHandler:new())
    client:getRequest():onWriteBodyStreamHandler(function(clientRequest)
      logger:finer('client request on write body')
      local drsh = request:getBodyStreamHandler()
      drsh:setStreamHandler(clientRequest:getBodyStreamHandler())
    end)
    local pr, cb = Promise.withCallback()
    client:connect():next(function()
      logger:finer('client connected')
      return client:sendRequest() -- TODO switch to fetch
    end):next(function()
      logger:finer('client send completed')
      return client:receiveResponseHeaders()
    end):next(function(remainingBuffer)
      local clientResponse = client:getResponse()
      logger:fine('client status code is %d, remaining buffer #%l', clientResponse:getStatusCode(), remainingBuffer)
      response:setStatusCode(clientResponse:getStatusCode())
      local respHdrs = HttpHeaders:new()
      respHdrs:addHeadersTable(clientResponse:getHeadersTable())
      -- TODO rewrite headers, location, cookie path
      response:setHeadersTable(respHdrs:getHeadersTable())
      clientResponse:setBodyStreamHandler(DelayedStreamHandler:new())
      response:onWriteBodyStreamHandler(function()
        logger:finer('response on write body')
        local drsh = clientResponse:getBodyStreamHandler()
        drsh:setStreamHandler(response:getBodyStreamHandler())
      end)
      cb()
      return client:receiveResponseBody(remainingBuffer)
    end):next(function()
      logger:finer('closing client')
      client:close()
    end, function(err)
      logger:fine('client error: %s', err)
      response:setStatusCode(HTTP_CONST.HTTP_INTERNAL_SERVER_ERROR, 'Internal Server Error')
      response:setBody('<p>Sorry something went wrong on our side.</p>')
      client:close()
      cb(err)
    end)
    return pr
  end

  function proxyHttpHandler:close()
    local pendings = self.pendings
    self.pendings = {}
    local count = 0
    for client, targetClient in pairs(pendings) do
      client:close()
      targetClient:close()
      count = count + 1
    end
    logger:fine('proxyHttpHandler:close() %d pending connect(s) closed', count)
  end

end)
