--- An HTTP client implementation that enable to send and receive @{jls.net.http.HttpMessage|message}.
-- @module jls.net.http.HttpClient
-- @pragma nostrip

local class = require('jls.lang.class')
local logger = require('jls.lang.logger'):get(...)
local TcpSocket = require('jls.net.TcpSocket')
local Promise = require('jls.lang.Promise')
local Url = require('jls.net.Url')
local Http1 = require('jls.net.http.Http1')
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
  return Http1.writeHeaders(tcpClient, request):next(function()
    logger:finer('sendRequest() writeHeaders() done')
    return Http1.writeBody(tcpClient, request)
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
-- end deprecated helpers

--[[--
The HttpClient class enables to send an HTTP request.
@usage
local event = require('jls.lang.event')
local HttpClient = require('jls.net.http.HttpClient')

local httpClient = HttpClient:new('https://www.openssl.org/')
httpClient:fetch('/'):next(function(response)
  print('status code is', response:getStatusCode())
  return response:text()
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
  -- @tparam table options A table describing the client options or the URL.
  -- @tparam string options.url The request URL.
  -- @tparam[opt] string options.host The request hostname.
  -- @tparam[opt] number options.port The request port number.
  -- @tparam[opt] boolean options.isSecure true to use a secure client.
  -- @tparam[opt] table options.secureContext the secure context options.
  -- @return a new HTTP client
  function httpClient:initialize(options)
    if type(options) == 'string' or Url:isInstance(options) then
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
      self.file = url:getFile()
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
    if self.isSecure then
      if type(options.secureContext) == 'table' then
        self:setSecureContext(options.secureContext)
      elseif options.h2 then
        self:setSecureContext({ alpnProtos = {'h2', 'http/1.1', 'http/1.0'} })
      end
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

  function httpClient:getUrl()
    local url = 'http'
    if self.isSecure then
      url = url..'s'
    end
    url = url..'://'
    if self.host then
      url = url..self.host
    else
      url = url..'localhost'
    end
    if self.port then
      url = url..self.port
    end
    if self.file then
      url = url..self.file
    end
  return url
  end

  function httpClient:getTcpClient()
    return self.tcpClient
  end

  function httpClient:connectV2()
    logger:finer('connectV2()')
    if self.connecting then
      return self.connecting
    elseif not self:isClosed() then
      return Promise.resolve(self)
    end
    self:close(false)
    local tcp
    if self.isSecure then
      tcp = secure.TcpSocket:new()
      tcp:sslInit(false, self.secureContext or SECURE_CONTEXT)
    else
      tcp = TcpSocket:new()
    end
    self.tcpClient = tcp
    local connecting = tcp:connect(self.host, self.port or 80)
    self.connecting = connecting
    connecting:next(function()
      logger:finer('connected %s', tcp)
      if self.isSecure and tcp.sslGetAlpnSelected then
        if tcp:sslGetAlpnSelected() == 'h2' then
          logger:fine('using HTTP/2')
          local http2 = Http2:new(tcp, false)
          -- To avoid unnecessary latency, clients are permitted to send additional frames to the server immediately after sending the client connection preface
          self.http2 = http2
          return http2:readStart({
            [Http2.SETTINGS.ENABLE_PUSH] = 0,
            [Http2.SETTINGS.HEADER_TABLE_SIZE] = 65536,
            [Http2.SETTINGS.INITIAL_WINDOW_SIZE] = 6291456,
            [Http2.SETTINGS.MAX_CONCURRENT_STREAMS] = 100,
            [Http2.SETTINGS.MAX_HEADER_LIST_SIZE] = 262144,
          })
        end
      end
    end):next(function()
      return self
    end):finally(function()
      self.connecting = nil
    end)
    return connecting
  end

  local function handleRedirect(client, options, request, response)
    if (response:getStatusCode() // 100) == 3 then
      local redirect = options.redirect or 'follow'
      if redirect == 'error' then
        return Promise.reject('redirected')
      end
      local redirectCount = request.redirectCount or 0
      redirectCount = redirectCount + 1
      local location = response:getHeader(HttpMessage.CONST.HEADER_LOCATION)
      if location and redirect == 'follow' and redirectCount < 20 then
        request.redirectCount = redirectCount
        logger:fine('redirected to "%s" (%d)', location, redirectCount)
        if response:getStatusCode() == 303 then
          request:setMethod('GET')
        end
        local url = Url.fromString(location)
        if url then
          if not(url:getHost() == client.host and url:getPort() == client.port and isUrlSecure(url) == client.isSecure) then
            local c = httpClient:new(url)
            request:setTarget(url:getFile())
            return response:consume():next(function()
              return c:fetch(request, options)
            end)
          end
          location = url:getFile()
        elseif string.sub(location, 1, 1) ~= '/' then
          location = request:getTargetPath()..'/'..location
        end
        if location ~= request:getTarget() then
          request:setTarget(location)
          return response:consume():next(function()
            return client:fetch(request, options)
          end)
        end
      end
    end
    return Promise.resolve(response)
  end

  local Stream = class.create(Http2.Stream, function(stream, super)

    function stream:onEndHeaders()
      super.onEndHeaders(self)
      local response = self.message
      local promise, cb = Promise.createWithCallback()
      response.consume = function()
        return promise
      end
      self.endStreamCallback = cb
      local p = handleRedirect(self.client, self.options, self.request, response)
      local endHeadersCallback = self.endHeadersCallback
      if endHeadersCallback then
        self.endHeadersCallback = nil
        p:next(Promise.callbackToNext(endHeadersCallback))
      end
    end

    function stream:onEndStream()
      local endStreamCallback = self.endStreamCallback
      if endStreamCallback then
        self.endStreamCallback = nil
        endStreamCallback()
      end
      super.onEndStream(self)
    end

    function stream:clearCallbacks(reason)
      local endStreamCallback = self.endStreamCallback
      if endStreamCallback then
        self.endStreamCallback = nil
        logger:fine('clear end stream %d callback due to "%s"', self.id, reason)
        endStreamCallback(reason)
      end
      local endHeadersCallback = self.endHeadersCallback
      if endHeadersCallback then
        self.endHeadersCallback = nil
        logger:fine('clear end stream %d headers callback due to "%s"', self.id, reason)
        endHeadersCallback(reason)
      end
    end

    function stream:onError(reason)
      super.onError(self, reason)
      self:clearCallbacks(reason)
    end

    function stream:close()
      super.close(self)
      self:clearCallbacks('closed')
    end

  end, function(Stream)

    function Stream.sendRequest(http2, client, options, request, response)
      local stream = Stream:new(http2, http2:nextStreamId(), response)
      http2:registerStream(stream)
      -- TODO shall we override response:close()?
      local promise, cb = Promise.createWithCallback()
      stream.endHeadersCallback = cb
      stream.client = client
      stream.options = options
      stream.request = request
      if request:isBodyEmpty() then
        stream:sendHeaders(request, true, request:getMethod() ~= 'CONNECT')
      else
        stream:sendHeaders(request, true):next(function()
          logger:finer('fetch write headers done')
          stream:sendBody(request)
        end)
      end
      return promise
    end

  end)

  --- Sends an HTTP request and receives a response.
  -- The response body must be consumed using its text(), json() or consume() method.
  -- @tparam string resource The request target path.
  -- @tparam[opt] table options A table describing the request options.
  -- @tparam[opt] string options.method The HTTP method, default is GET.
  -- @tparam[opt] table options.headers The HTTP request headers.
  -- @tparam[opt] string options.body The HTTP request body, default is empty body.
  -- @tparam[opt] string options.redirect How to handle a redirect: follow, error or manual.
  -- @return a promise that resolves to the HTTP @{jls.net.http.HttpMessage|response}
  function httpClient:fetch(resource, options)
    if type(options) ~= 'table' then
      options = {}
    end
    local request
    if HttpMessage:isInstance(resource) and resource:isRequest() then
      request = resource
    elseif type(resource) == 'string' or self.file and resource == nil then
      request = HttpMessage:new()
      request:setTarget(resource or self.file)
      request:setMethod('GET')
    else
      error('invalid argument')
    end
    if options.method then
      request:setMethod(options.method)
    end
    if options.headers then
      request:addHeadersTable(options.headers)
    end
    if options.body then
      request:setBody(options.body)
    end
    local url = Url.fromString(request:getTarget())
    local hostPort
    if url then
      hostPort = formatHostPort(url:getHost(), url:getPort())
    else
      hostPort = formatHostPort(self.host, self.port)
    end
    request:setHeader(HttpMessage.CONST.HEADER_HOST, hostPort)
    local response = HttpMessage:new()
    return self:connectV2():next(function()
      if self.http2 then
        logger:fine('fetch is using HTTP/2')
        return Stream.sendRequest(self.http2, self, options, request, response)
      end
      logger:fine('fetch is using HTTP/1')
      request:applyBodyLength()
      -- keep alive the connection by default
      if not request:getHeader(HttpMessage.CONST.HEADER_CONNECTION) then
        local connection
        if request:getVersion() == HttpMessage.CONST.VERSION_1_0 then
          connection = HttpMessage.CONST.CONNECTION_CLOSE
        else
          connection = HttpMessage.CONST.CONNECTION_KEEP_ALIVE
        end
        request:setHeader(HttpMessage.CONST.HEADER_CONNECTION, connection)
      end
      local queuePromise = self.queuePromise or Promise.resolve()
      local queueNext
      self.queuePromise, queueNext = Promise.createWithCallback()
      return queuePromise:next(function()
        return self:connectV2() -- we stick to HTTP/1
      end):next(function()
        return Http1.writeHeaders(self.tcpClient, request)
      end):next(function()
        logger:finer('fetch write headers done')
        return Http1.writeBody(self.tcpClient, request)
      end):next(function()
        logger:finer('fetch write body done')
        return Http1.readHeader(self.tcpClient, response, self.remnant)
      end):next(function(buffer)
        logger:finer('fetch read headers done')
        local connection = response:getHeader(HttpMessage.CONST.HEADER_CONNECTION)
        local connectionClose
        if connection then
          connectionClose = strings.equalsIgnoreCase(connection, HttpMessage.CONST.CONNECTION_CLOSE)
        else
          connectionClose = response:getVersion() == HttpMessage.CONST.VERSION_1_0
        end
        -- TODO Always read body after resolving consume promise
        -- TODO shall we override response:close()?
        local promise
        response.consume = function(message)
          if not promise then
            logger:finer('fetch reading body')
            local statusCode = message:getStatusCode()
            if statusCode == 204 or statusCode == 304 or (statusCode // 100 == 1) or request:getMethod() == 'HEAD' then
              message:getBodyStreamHandler():onData(nil)
              self.remnant = buffer
              promise = Promise.resolve()
            else
              promise = Http1.readBody(self.tcpClient, message, buffer):next(function(remnant)
                logger:finer('fetch read body done')
                self.remnant = remnant
              end)
            end
            promise:finally(function()
              if connectionClose then
                self:closeClient(false)
              end
              queueNext()
            end)
          end
          return promise
        end
        return handleRedirect(self, options, request, response)
      end)
    end)
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

  function httpClient:isClosed()
    return self.tcpClient == nil or self.tcpClient:isClosed()
  end

  --- Closes this HTTP client.
  -- @tparam[opt] function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the client is closed.
  function httpClient:close(callback)
    self.remnant = nil
    local http2 = self.http2
    if http2 then
      self.http2 = nil
      http2:close()
    end
    self:closeRequest() -- deprecated
    return self:closeClient(callback)
  end


  -- deprecated

  function httpClient:initializeV1(options)
    logger:finer('initializeV1(...)')
    options = options or {}
    local request = HttpMessage:new()
    self.request = request
    if type(options.headers) == 'table' then
      request:addHeadersTable(options.headers)
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
    if type(options.maxRedirectCount) == 'number' then
      self.maxRedirectCount = options.maxRedirectCount
    elseif options.followRedirect == true then
      self.maxRedirectCount = 3
    else
      self.maxRedirectCount = 0
    end
    -- add accept headers
  end

  function httpClient:setUrl(url)
    logger:finer('setUrl(%s)', url)
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
    logger:finer('connect()')
    if self.tcpClient then
      return Promise.resolve(self)
    end
    return self:reconnectV1()
  end

  function httpClient:reconnectV1()
    logger:finer('reconnect()')
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
    logger:warn('HttpClient sendRequest() is deprecated, please use fetch()')
    self.response = HttpMessage:new()
    self.response:bufferBody()
    -- close the connection by default
    if not self.request:getHeader(HttpMessage.CONST.HEADER_CONNECTION) then
      self.request:setHeader(HttpMessage.CONST.HEADER_CONNECTION, HttpMessage.CONST.CONNECTION_CLOSE)
    end
    return sendRequest(self.tcpClient, self.request)
  end

  function httpClient:receiveResponseHeaders()
    logger:finer('receiveResponseHeaders()')
    local response = HttpMessage:new()
    local hsh = HeaderStreamHandler:new(response)
    return hsh:read(self.tcpClient):next(function(remainingBuffer)
      if logger:isLoggable(logger.FINE) then
        logger:finer('header done, status code is %d, remainingBuffer is #%s',
          response:getStatusCode(), remainingBuffer and #remainingBuffer)
      end
      if self.maxRedirectCount > 0 and (response:getStatusCode() // 100) == 3 then
        local location = response:getHeader(HttpMessage.CONST.HEADER_LOCATION)
        if location then
          logger:finer('redirected #%d to "%s"', self.maxRedirectCount, location)
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
    logger:finest('receiveResponseBody(%l)', buffer)
    local connection = self.response:getHeader(HttpMessage.CONST.HEADER_CONNECTION)
    local connectionClose
    if connection then
      connectionClose = strings.equalsIgnoreCase(connection, HttpMessage.CONST.CONNECTION_CLOSE)
    else
      connectionClose = self.response:getVersion() ~= HttpMessage.CONST.VERSION_1_1
    end
    return Http1.readBody(self.tcpClient, self.response, buffer):finally(function()
      self:closeRequest()
      if connectionClose then
        self:closeClient(false)
      end
    end)
  end

  function httpClient:receiveResponse()
    logger:finest('receiveResponse()')
    return self:receiveResponseHeaders():next(function(remainingBuffer)
      logger:finest('receiveResponse() headers done')
      return self:receiveResponseBody(remainingBuffer)
    end)
  end

  function httpClient:sendReceive()
    logger:finer('sendReceive()')
    return self:connect():next(function()
      return self:sendRequest()
    end):next(function()
      logger:finer('send completed')
      return self:receiveResponse()
    end):next(function()
      logger:finer('receive completed')
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
