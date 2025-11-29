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
local strings = require('jls.util.strings')
local secure

local function formatHostPort(host, port, isSecure)
  if port and port ~= (isSecure and 443 or 80) then
    return string.format('%s:%d', host, port)
  end
  return host
end

local function isSchemeSecured(scheme)
  return scheme == 'https' or scheme == 'wss'
end

local SECURE_CONTEXT

local function isUrlSecure(url)
  return isSchemeSecured(url:getProtocol())
end

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
return class.create(function(httpClient, _, HttpClient)

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

  function httpClient:connectV2() -- TODO Rename?
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

  function httpClient:getSubClient(url)
    local n = url:getProtocol()..'://'..url:getHostPort()
    if self.clients then
      local c = self.clients[n]
      if c then
        return c
      end
    else
      self.clients = {}
    end
    logger:fine('create sub client "%s"', n)
    local c = HttpClient:new(url)
    c.secureContext = self.secureContext
    self.clients[n] = c
    return c
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
            local c = client:getSubClient(url)
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
      local promise, cb = Promise.withCallback()
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
      local promise, cb = Promise.withCallback()
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
      hostPort = url:getHostPort()
    else
      hostPort = formatHostPort(self.host, self.port, self.isSecure)
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
      self.queuePromise, queueNext = Promise.withCallback()
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
    if self.clients then
      for n, client in pairs(self.clients) do
        logger:fine('closing sub client "%s"', n)
        client:close()
      end
      self.clients = nil
    end
    return self:closeClient(callback)
  end

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
