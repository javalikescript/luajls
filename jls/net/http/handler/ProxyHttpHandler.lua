--- Provide a simple HTTP handler that proxies requests.
-- See https://tools.ietf.org/html/rfc7230 and https://tools.ietf.org/html/rfc7231
-- @module jls.net.http.handler.ProxyHttpHandler
-- @pragma nostrip

local logger = require('jls.lang.logger')
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

  function proxyHttpHandler:acceptMethod(httpExchange, method)
    return HttpExchange.methodAllowed(httpExchange, ALLOWED_METHODS)
  end

  function proxyHttpHandler:acceptHost(httpExchange, host)
    logger:info('Proxy host "'..tostring(host)..'"')
    if host == nil then
      HttpExchange.forbidden(httpExchange)
      return false
    end
    return true
  end

  function proxyHttpHandler:getBaseUrl(httpExchange)
    if self.baseUrls then
      self.baseUrlIndex = (self.baseUrlIndex % #self.baseUrls) + 1
      local baseUrl = self.baseUrls[self.baseUrlIndex]
      return baseUrl
    end
    local hostport = httpExchange:getRequest():getHeader(HTTP_CONST.HEADER_HOST)
    if hostport and hostport ~= '' then
      return 'http://'..hostport
    end
    return nil
  end

  function proxyHttpHandler:getTargetUrl(httpExchange)
    if self.isReverse then
      local baseUrl = self:getBaseUrl(httpExchange)
      if baseUrl then
        local path = httpExchange:getRequestPath()
        if path then
          return Url.fromString(baseUrl..string.gsub(path, '^/*', '/'))
        end
      end
    else
      local target = httpExchange:getRequest():getTarget()
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
        if logger:isLoggable(logger.FINE) then
          logger:fine('proxyHttpHandler tunnel error "'..tostring(err)..'"')
        end
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

  function proxyHttpHandler:handleConnect(httpExchange)
    local hostport = httpExchange:getRequest():getTarget()
    local host, port = string.match(hostport, '^(.+):(%d+)$')
    if not host then
      HttpExchange.badRequest(httpExchange)
      return
    end
    port = tonumber(port) or 443
    if port ~= 443 and not self.allowConnectAnyPort then
      HttpExchange.forbidden(httpExchange)
      return
    end
    if not self:acceptHost(httpExchange, host) then
      return
    end
    if logger:isLoggable(logger.FINER) then
      logger:finer('proxyHttpHandler connecting to "'..hostport..'"')
    end
    local client
    return Promise:new(function(resolve, reject)
      local targetClient = TcpSocket:new()
      targetClient:connect(host, port):next(function()
        if logger:isLoggable(logger.FINE) then
          logger:fine('proxyHttpHandler connected to "'..hostport..'"')
        end
        httpExchange.applyKeepAlive = returnFalse
        function httpExchange.close()
          client = httpExchange:removeClient()
          self.pendings[client] = targetClient
          HttpExchange.prototype.close(httpExchange)
          local onStreamClosed = function()
            if self.pendings[client] then
              if logger:isLoggable(logger.FINE) then
                logger:fine('proxyHttpHandler connect to "'..hostport..'" closed')
              end
              self.pendings[client] = nil
              client:close()
              targetClient:close()
            end
          end
          connectStream(client, targetClient, onStreamClosed)
          connectStream(targetClient, client, onStreamClosed)
        end
        HttpExchange.ok(httpExchange)
        resolve()
      end, function(err)
        if logger:isLoggable(logger.FINE) then
          logger:fine('proxyHttpHandler connect error "'..tostring(err)..'"')
        end
        if client then
          client:close()
        end
        reject('Cannot connect')
      end)
    end)
  end

  function proxyHttpHandler:handle(httpExchange)
    local request = httpExchange:getRequest()
    local response = httpExchange:getResponse()
    local method = request:getMethod()
    if method == HTTP_CONST.METHOD_CONNECT and self.allowConnect then
      return self:handleConnect(httpExchange)
    end
    if not self:acceptMethod(httpExchange, method) then
      return
    end
    local targetUrl = self:getTargetUrl(httpExchange)
    if not targetUrl then
      HttpExchange.badRequest(httpExchange)
      return
    end
    if not self:acceptHost(httpExchange, targetUrl:getHost()) then
      return
    end
    if logger:isLoggable(logger.FINE) then
      logger:fine('proxyHttpHandler forward to "'..targetUrl:toString()..'"')
    end
    -- See https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Forwarded
    local headers = HttpHeaders:new()
    headers:setHeadersTable(request:getHeadersTable())
    local hostport = request:getHeader(HTTP_CONST.HEADER_HOST)
    if hostport then
      local forwarded = 'host='..hostport..';proto='..targetUrl:getProtocol()
      local by = httpExchange:clientAsString()
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
      logger:finer('proxyHttpHandler client request on write body')
      local drsh = request:getBodyStreamHandler()
      drsh:setStreamHandler(clientRequest:getBodyStreamHandler())
    end)
    local pr, cb = Promise.createWithCallback()
    client:connect():next(function()
      logger:finer('proxyHttpHandler client connected')
      return client:sendRequest()
    end):next(function()
      logger:finer('proxyHttpHandler client send completed')
      return client:receiveResponseHeaders()
    end):next(function(remainingBuffer)
      local clientResponse = client:getResponse()
      if logger:isLoggable(logger.FINE) then
        logger:fine('proxyHttpHandler client status code is '..tostring(clientResponse:getStatusCode())..
          ', remaining buffer #'..tostring(remainingBuffer and #remainingBuffer))
      end
      response:setStatusCode(clientResponse:getStatusCode())
      local respHdrs = HttpHeaders:new()
      respHdrs:setHeadersTable(clientResponse:getHeadersTable())
      -- TODO rewrite headers, location, cookie path
      response:setHeadersTable(respHdrs:getHeadersTable())
      clientResponse:setBodyStreamHandler(DelayedStreamHandler:new())
      response:onWriteBodyStreamHandler(function()
        logger:finer('proxyHttpHandler response on write body')
        local drsh = clientResponse:getBodyStreamHandler()
        drsh:setStreamHandler(response:getBodyStreamHandler())
      end)
      cb()
      return client:receiveResponseBody(remainingBuffer)
    end):next(function()
      logger:finer('proxyHttpHandler closing client')
      client:close()
    end, function(err)
      if logger:isLoggable(logger.FINE) then
        logger:fine('proxyHttpHandler client error: '..tostring(err))
      end
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
    if logger:isLoggable(logger.FINE) then
      logger:fine('proxyHttpHandler:close() '..tostring(count)..' pending connect(s) closed')
    end
  end

end)
