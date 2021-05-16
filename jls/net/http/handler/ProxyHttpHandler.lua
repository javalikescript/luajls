--- Provide a simple HTTP handler that proxies requests.
-- @module jls.net.http.handler.ProxyHttpHandler
-- @pragma nostrip

local logger = require('jls.lang.logger')
local HttpClient = require('jls.net.http.HttpClient')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local HttpExchange = require('jls.net.http.HttpExchange')
local DelayedStreamHandler = require('jls.io.streams.DelayedStreamHandler')
local Promise = require('jls.lang.Promise')
local URL = require('jls.net.URL')
local TcpClient = require('jls.net.TcpClient')

--[[
See
https://tools.ietf.org/html/rfc7230
https://tools.ietf.org/html/rfc7231
]]

--- A ProxyHttpHandler class.
-- @type ProxyHttpHandler
return require('jls.lang.class').create('jls.net.http.HttpHandler', function(proxyHttpHandler, super)

  --- Creates a proxy @{HttpHandler}.
  function proxyHttpHandler:initialize()
    self.allowConnect = false
    self.isReverse = false
    self.protocol = 'http'
  end

  --- Configures this proxy to forward requests.
  -- @tparam[opt] boolean allowConnect true to allow connect method.
  -- @treturn ProxyHttpHandler this proxy for chaining.
  function proxyHttpHandler:configureForward(allowConnect)
    self.isReverse = false
    self.allowConnect = allowConnect == true
    return self
  end

  --- Configures this proxy as reverse proxy.
  -- @tparam[opt] string baseUrl a base URL to forward requests to.
  -- @treturn ProxyHttpHandler this proxy for chaining.
  function proxyHttpHandler:configureReverse(baseUrl)
    self.isReverse = true
    self:setBaseUrl(baseUrl)
    return self
  end

  function proxyHttpHandler:setBaseUrl(baseUrl)
    if baseUrl then
      self.baseUrl = string.gsub(baseUrl, '/+$', '')
    else
      self.baseUrl = nil
    end
    return self
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
    if self.baseUrl then
      return self.baseUrl
    end
    local hostport = httpExchange:getRequest():getHeader(HTTP_CONST.HEADER_HOST)
    if not hostport or hostport == '' then
      return nil
    end
    local host, port = string.match(hostport, '^(.+):(%d+)$')
    if not host then
      host = hostport
    elseif port then
      port = tonumber(port)
    end
    local proto = self.protocol
    if port == 443 then
      proto = 'https'
      port = nil
    end
    if port then
      return proto..'://'..host..':'..tostring(port)
    end
    return proto..'://'..host
  end

  function proxyHttpHandler:getTargetUrl(httpExchange)
    if self.isReverse then
      local baseUrl = self:getBaseUrl(httpExchange)
      if baseUrl then
        local path = httpExchange:getRequestArguments()
        if path then
          return URL.fromString(baseUrl..string.gsub(path, '^/*', '/'))
        end
      end
    else
      local target = httpExchange:getRequest():getTarget()
      return URL.fromString(target)
    end
    return nil
  end

  local function connectStream(fromClient, toClient)
    fromClient:readStart(function(err, data)
      if err then
        if logger:isLoggable(logger.FINE) then
          logger:fine('proxyHttpHandler tunnel error "'..tostring(err)..'"')
        end
      elseif data then
        toClient:write(data)
        return
      end
      toClient:close()
      fromClient:close()
    end)
  end

  function proxyHttpHandler:handleConnect(httpExchange)
    local hostport = httpExchange:getRequest():getTarget()
    local host, port = string.match(hostport, '^(.+):(%d+)$')
    if not host then
      HttpExchange.badRequest(httpExchange)
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
      local targetClient = TcpClient:new()
      targetClient:connect(host, tonumber(port) or 80):next(function()
        if logger:isLoggable(logger.FINE) then
          logger:fine('proxyHttpHandler connected to "'..hostport..'"')
        end
        HttpExchange.ok(httpExchange)
        httpExchange:getResponse():setHeader(HTTP_CONST.HEADER_CONNECTION, HTTP_CONST.CONNECTION_CLOSE)
        function httpExchange:close()
          client = httpExchange:removeClient()
          HttpExchange.prototype.close(httpExchange)
          connectStream(client, targetClient)
          connectStream(targetClient, client)
        end
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

  local ALLOWED_METHODS = {HTTP_CONST.METHOD_GET, HTTP_CONST.METHOD_HEAD, HTTP_CONST.METHOD_POST, HTTP_CONST.METHOD_PUT, HTTP_CONST.METHOD_DELETE}

  function proxyHttpHandler:handle(httpExchange)
    local request = httpExchange:getRequest()
    local response = httpExchange:getResponse()
    local method = request:getMethod()
    if method == HTTP_CONST.METHOD_CONNECT then
      if not self.allowConnect then
        HttpExchange.methodNotAllowed(httpExchange)
      else
        return self:handleConnect(httpExchange)
      end
      return
    end
    if not HttpExchange.methodAllowed(httpExchange, ALLOWED_METHODS) then
      return
    end
    local targetUrl = self:getTargetUrl(httpExchange)
    if not targetUrl then
      httpExchange:setResponseStatusCode(HTTP_CONST.HTTP_FORBIDDEN, 'Forbidden', '<p>The server cannot proxy your request to the specified host.</p>')
      return
    end
    if not self:acceptHost(httpExchange, targetUrl:getHost()) then
      return
    end
    if logger:isLoggable(logger.FINE) then
      logger:fine('proxyHttpHandler forward to "'..targetUrl:toString()..'"')
    end
    -- See https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Forwarded
    local client = HttpClient:new({
      url = targetUrl:toString(),
      method = method,
      headers = request:getHeadersTable()
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
      response:setHeadersTable(clientResponse:getHeadersTable())
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

end)
