--- An HTTP client implementation that enable to send and receive @{jls.net.http.HttpMessage|message}.
-- @module jls.net.http.HttpClient
-- @pragma nostrip

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local StreamHandler = require('jls.io.StreamHandler')
local TcpSocket = require('jls.net.TcpSocket')
local Promise = require('jls.lang.Promise')
local Url = require('jls.net.Url')
local Http2 = require('jls.net.http.Http2')
local HttpMessage = require('jls.net.http.HttpMessage')
local HeaderStreamHandler = require('jls.net.http.HeaderStreamHandler')
local strings = require('jls.util.strings')
local secure

local function formatHostPort(host, port)
  if port then
    return string.format('%s:%d', host, port)
  end
  return host
end

local function isSchemeSecured(scheme)
  return scheme == 'https' or scheme == 'wss'
end

local SECURE_CONTEXT

-- deprecated helpers
local function sendRequest(tcpClient, request)
  logger:finer('sendRequest()')
  request:applyBodyLength()
  return request:writeHeaders(tcpClient):next(function()
    logger:finer('sendRequest() writeHeaders() done')
    return request:writeBody(tcpClient)
  end)
end
local getSecure = require('jls.lang.loader').singleRequirer('jls.net.secure')
local function getHostHeader(host, port)
  if port then
    return host..':'..tostring(port)
  end
  return host
end
local function isUrlSecure(url)
  return isSchemeSecured(url:getProtocol())
end
local function sameClient(url1, url2)
  return url1:getHost() == url2:getHost() and url1:getPort() == url2:getPort() and isUrlSecure(url1) == isUrlSecure(url2)
end

--[[--
The HttpClient class enables to send an HTTP request.
@usage
local event = require('jls.lang.event')
local HttpClient = require('jls.net.http.HttpClient')

local httpClient = HttpClient:new('https://www.openssl.org/')
httpClient:fetch('/'):next(function(response)
  print('status code is', response:getStatusCode())
  return response:readBody()
end):next(function(body)
  print(body)
  httpClient:close()
end)
event:loop()
@type HttpClient
]]
return class.create(function(httpClient)

  --- Creates a new HTTP client.
  -- @function HttpClient:new
  -- @tparam table options A table describing the client options.
  -- @tparam string options.url The request URL.
  -- @tparam[opt] string options.host The request hostname.
  -- @tparam[opt] number options.port The request port number.
  -- @tparam[opt] boolean options.isSecure true to use a secure client.
  -- @tparam[opt] table options.secureContext the secure context options.
  -- @return a new HTTP client
  function httpClient:initialize(options)
    if type(options) == 'string' then
      options = { url = options }
    elseif options == nil then
      options = {}
    elseif type(options) ~= 'table' then
      error('invalid argument')
    end
    if options.url then
      local url = class.asInstance(Url, options.url)
      self.isSecure = isSchemeSecured(url:getProtocol())
      self.host = url:getHost()
      self.port = url:getPort()
    else
      if options.isSecure ~= nil then
        self.isSecure = options.isSecure
      else
        self.isSecure = isSchemeSecured(options.scheme or options.protocol)
      end
      self.host = options.host
      self.port = options.port
    end
    if self.isSecure and not secure then
      secure = require('jls.net.secure')
    end
    if type(options.secureContext) == 'table' then
      self:setSecureContext(options.secureContext)
    end
    self:initializeV1(options) -- deprecated
  end

  function httpClient:getSecureContext()
    return self.secureContext
  end

  function httpClient:setSecureContext(secureContext)
    if secure and secureContext then
      self.secureContext = class.asInstance(secure.Context, secureContext)
    else
      self.secureContext = nil
    end
  end

  function httpClient:getTcpClient()
    return self.tcpClient
  end

  function httpClient:closeClient(callback)
    local tcpClient = self.tcpClient
    if tcpClient then
      self.tcpClient = nil
      return tcpClient:close(callback)
    end
    if callback then
      callback()
    elseif callback == nil then
      return Promise.resolve()
    end
  end

  --- Closes this HTTP client.
  -- @treturn jls.lang.Promise a promise that resolves once the client is closed.
  function httpClient:close(callback)
    local http2 = self.http2
    if http2 then
      self.http2 = nil
      http2:close()
    end
    self:closeRequest() -- deprecated
    return self:closeClient(callback)
  end

  function httpClient:isClosed()
    return self.tcpClient == nil
  end

  function httpClient:onHttp2EndHeaders(stream)
    logger:finer('httpClient:onHttp2EndHeaders()')
    local response = stream.message
    local promise, cb = Promise.createWithCallback()
    response.readBody = function(message, sh)
      logger:finer('httpClient response.readBody()')
      if sh and StreamHandler:isInstance(sh) then
        message:setBodyStreamHandler(sh)
      else
        message:bufferBody()
      end
      return promise
    end
    local callback = stream.callback
    stream.callback = cb
    callback(nil, response)
  end

  function httpClient:onHttp2EndStream(stream)
    logger:finer('httpClient:onHttp2EndStream()')
    local callback = stream.callback
    stream.callback = nil
    callback(nil, stream.message:getBody())
  end

  function httpClient:onHttp2Ping(http2)
  end

  function httpClient:onHttp2Error(stream, reason)
    logger:warn('httpClient:onHttp2Error(%s, %s)', stream and stream.id or '-', reason)
  end

  function httpClient:connectV2()
    logger:finer('httpClient:connectV2()')
    if self.tcpClient then
      return Promise.resolve(self)
    end
    self.http2 = nil
    self.remnant = nil
    self:close(false)
    if self.isSecure then
      self.tcpClient = secure.TcpSocket:new()
      self.tcpClient:sslInit(false, self.secureContext or SECURE_CONTEXT)
    else
      self.tcpClient = TcpSocket:new()
    end
    -- TODO handle proxy
    return self.tcpClient:connect(self.host, self.port or 80):next(function()
      return self
    end):next(function()
      if self.isSecure and self.tcpClient.sslGetAlpnSelected then
        if self.tcpClient:sslGetAlpnSelected() == 'h2' then
          logger:fine('using HTTP/2')
          self.http2 = Http2:new(self.tcpClient, false, self)
          self.http2:readStart()
        end
      end
    end)
  end

  local readBody = HttpMessage.prototype.readBody

  --- Sends an HTTP request and receives the response.
  -- @tparam string resource The request target path.
  -- @tparam table options A table describing the request options.
  -- @tparam[opt] string options.method The HTTP method, default is GET.
  -- @tparam[opt] table options.headers The HTTP request headers.
  -- @tparam[opt] string options.body The HTTP request body, default is empty body.
  -- @return a promise that resolve to the HTTP response
  function httpClient:fetch(resource, options)
    local request
    if HttpMessage:isInstance(resource) then
      request = resource
    elseif type(resource) == 'string' then
      request = HttpMessage:new()
      request:setTarget(resource)
      request:setMethod('GET')
      if type(options) == 'table' then
        if options.method then
          request:setMethod(options.method)
        end
        if options.headers then
          request:setHeadersTable(options.headers)
        end
        if options.body then
          request:setBody(options.body)
        end
      end
    else
      error('invalid argument')
    end
    request:applyBodyLength()
    local response = HttpMessage:new()
    return self:connectV2():next(function()
      if self.http2 then
        logger:info('fetch is using HTTP/2')
        local stream = self.http2:newStream(response)
        local promise, cb = Promise.createWithCallback()
        stream.callback = cb
        stream:sendHeaders(request):next(function()
          logger:finer('fetch write headers done')
          stream:sendBody(request)
        end)
        return promise
      end
      request:setHeader(HttpMessage.CONST.HEADER_HOST, formatHostPort(self.host, self.port))
      return request:writeHeaders(self.tcpClient):next(function()
        logger:finer('fetch write headers done')
        return request:writeBody(self.tcpClient)
      end):next(function()
        logger:finer('fetch write body done')
        local hsh = HeaderStreamHandler:new(response)
        return hsh:read(self.tcpClient, self.remnant)
      end):next(function(buffer)
        logger:finer('fetch read headers done')
        -- TODO handle redirect on the same client
        response.readBody = function(message, sh)
          if sh and StreamHandler:isInstance(sh) then
            message:setBodyStreamHandler(sh)
          else
            message:bufferBody()
          end
          logger:finer('fetch reading body')
          return readBody(message, self.tcpClient, buffer):next(function(remnant)
            logger:finer('fetch read body done')
            self.remnant = remnant
            return message:getBody()
          end)
        end
        return response
      end)
    end)
  end


  -- deprecated

  function httpClient:initializeV1(options)
    logger:finer('httpClient:initializeV1(...)')
    options = options or {}
    local request = HttpMessage:new()
    self.request = request
    if type(options.headers) == 'table' then
      request:setHeadersTable(options.headers)
    end
    request:setMethod(options.method or 'GET')
    if options.url then
      request.url = class.asInstance(Url, options.url)
    else
      local protocol, host, port, target = 'http', 'localhost', nil, '/'
      if type(options.protocol) == 'string' then
        protocol = options.protocol
      elseif options.isSecure == true then
        protocol = protocol..'s'
      end
      if type(options.host) == 'string' then
        host = options.host
      end
      if type(options.port) == 'number' then
        port = options.port
      end
      if type(options.target) == 'string' then
        target = options.target
      end
      request.url = Url:new(protocol, host, port, target)
    end
    request:setTarget(request.url:getFile())
    if options.body then
      request:setBody(options.body)
    end
    if type(options.proxyHost) == 'string' then
      self.proxyHost = options.proxyHost
      if type(options.proxyPort) == 'number' then
        self.proxyPort = options.proxyPort
      else
        self.proxyPort = 8080
      end
    end
    self.maxRedirectCount = 0
    if type(options.maxRedirectCount) == 'number' then
      self.maxRedirectCount = options.maxRedirectCount
    elseif options.followRedirect == true then
      self.maxRedirectCount = 3
    end
    -- add accept headers
  end

  function httpClient:setUrl(url)
    if logger:isLoggable(logger.FINER) then
      logger:finer('httpClient:setUrl(%s)', url)
    end
    local u = class.asInstance(Url, url)
    -- do our best to keep the client
    if self.tcpClient and not sameClient(u, self.request.url) then
      self:closeClient(false)
    end
    self.request.url = u
    self.request:setTarget(self.request.url:getFile())
    return self
  end

  function httpClient:connect()
    logger:finer('httpClient:connect()')
    if self.tcpClient then
      return Promise.resolve(self)
    end
    return self:reconnectV1()
  end

  function httpClient:reconnectV1()
    logger:finer('httpClient:reconnect()')
    self:closeClient(false)
    local request = self.request
    local url = request.url
    local isSecure = isUrlSecure(url)
    local host = url:getHost()
    local port = url:getPort()
    if isSecure and getSecure() then
      self.tcpClient = getSecure().TcpSocket:new()
      self.tcpClient:sslInit(false, self.secureContext or SECURE_CONTEXT)
    else
      self.tcpClient = TcpSocket:new()
    end
    if self.proxyHost then
      if isSecure then
        local connectTcp = TcpSocket:new()
        local connectRequest = HttpMessage:new()
        local connectResponse = HttpMessage:new()
        connectRequest:setMethod('CONNECT')
        local proxyTarget = getHostHeader(self.proxyHost, self.proxyPort)
        connectRequest:setTarget(proxyTarget)
        connectRequest:setHeader(HttpMessage.CONST.HEADER_HOST, proxyTarget)
        return sendRequest(connectTcp, connectRequest):next(function()
          local hsh = HeaderStreamHandler:new(connectResponse)
          return hsh:read(connectTcp)
        end):next(function(remainingBuffer)
          self.tcpClient.tcp = connectTcp.tcp
          connectTcp.tcp = nil
          return connectTcp:onConnected(host, remainingBuffer)
        end):next(function()
          return self
        end)
      else
        -- see RFC 7230 5.3.2. absolute-form
        local u = Url.format({
          scheme = 'http',
          host = host,
          port = port,
          path = request:getTarget()
        })
        request:setUrl(u)
        request:setHeader(HttpMessage.CONST.HEADER_HOST, getHostHeader(host, port))
        return self.tcpClient:connect(self.proxyHost, self.proxyPort):next(function()
          return self
        end)
      end
    end
    request:setHeader(HttpMessage.CONST.HEADER_HOST, getHostHeader(host, port))
    return self.tcpClient:connect(host, port or 80):next(function()
      return self
    end)
  end

  function httpClient:closeRequest()
    if self.request then
      self.request:close()
    end
    if self.response then
      self.response:close()
    end
  end

  function httpClient:getRequest()
    return self.request
  end

  function httpClient:getResponse()
    return self.response
  end

  function httpClient:processResponseHeaders()
  end

  function httpClient:sendRequest()
    logger:finer('httpClient:sendRequest()')
    self.response = HttpMessage:new()
    self.response:bufferBody()
    -- close the connection by default
    if not self.request:getHeader(HttpMessage.CONST.HEADER_CONNECTION) then
      self.request:setHeader(HttpMessage.CONST.HEADER_CONNECTION, HttpMessage.CONST.CONNECTION_CLOSE)
    end
    return sendRequest(self.tcpClient, self.request)
  end

  function httpClient:receiveResponseHeaders()
    logger:finer('httpClient:receiveResponseHeaders()')
    local response = HttpMessage:new()
    local hsh = HeaderStreamHandler:new(response)
    return hsh:read(self.tcpClient):next(function(remainingBuffer)
      if logger:isLoggable(logger.FINE) then
        logger:finer('httpClient:receiveResponseHeaders() header done, status code is %d, remainingBuffer is #%s',
          response:getStatusCode(), remainingBuffer and #remainingBuffer)
      end
      if self.maxRedirectCount > 0 and (response:getStatusCode() // 100) == 3 then
        local location = response:getHeader(HttpMessage.CONST.HEADER_LOCATION)
        if location then
          logger:finer('httpClient:receiveResponseHeaders() redirected #%d to "%s"', self.maxRedirectCount, location)
          self.maxRedirectCount = self.maxRedirectCount - 1
          return self:closeClient():next(function()
            self:setUrl(location) -- TODO Is it ok to overwrite the url?
            return self:connect()
          end):next(function()
            return sendRequest(self.tcpClient, self.request)
          end):next(function()
            return self:receiveResponseHeaders()
          end)
        end
      end
      self.response:setLine(response:getLine())
      self.response:setHeadersTable(response:getHeadersTable())
      self:processResponseHeaders()
      return remainingBuffer
    end)
  end

  function httpClient:receiveResponseBody(buffer)
    logger:finest('httpClient:receiveResponseBody(%s)', buffer and #buffer)
    local connection = self.response:getHeader(HttpMessage.CONST.HEADER_CONNECTION)
    local connectionClose
    if connection then
      connectionClose = strings.equalsIgnoreCase(connection, HttpMessage.CONST.CONNECTION_CLOSE)
    else
      connectionClose = self.response:getVersion() ~= HttpMessage.CONST.VERSION_1_1
    end
    return self.response:readBody(self.tcpClient, buffer):finally(function()
      self:closeRequest()
      if connectionClose then
        self:closeClient(false)
      end
    end)
  end

  function httpClient:receiveResponse()
    logger:finest('httpClient:receiveResponse()')
    return self:receiveResponseHeaders():next(function(remainingBuffer)
      logger:finest('httpClient:receiveResponse() headers done')
      return self:receiveResponseBody(remainingBuffer)
    end)
  end

  --- Sends the request then receives the response.
  -- This client is connected if necessary.
  --
  -- **Note:** This method is deprecated, please consider using the fetch one.
  -- @treturn jls.lang.Promise a promise that resolves to the @{HttpMessage} received.
  function httpClient:sendReceive()
    logger:finer('httpClient:sendReceive()')
    return self:connect():next(function()
      return self:sendRequest()
    end):next(function()
      logger:finer('httpClient:sendReceive() send completed')
      return self:receiveResponse()
    end):next(function()
      logger:finer('httpClient:sendReceive() receive completed')
      return self.response
    end)
  end

end, function(HttpClient)

  function HttpClient.getSecureContext()
    return DEFAULT_SECURE_CONTEXT
  end

  function HttpClient.setSecureContext(secureContext)
    DEFAULT_SECURE_CONTEXT = secureContext
    if secureContext then
      DEFAULT_SECURE_CONTEXT = class.asInstance(require('jls.net.secure').Context, secureContext)
    else
      DEFAULT_SECURE_CONTEXT = nil
    end
  end

end)
