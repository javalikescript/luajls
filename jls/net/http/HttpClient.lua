--- An HTTP client implementation that enable to send and receive @{jls.net.http.HttpMessage|message}.
-- @module jls.net.http.HttpClient
-- @pragma nostrip

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local TcpSocket = require('jls.net.TcpSocket')
local Promise = require('jls.lang.Promise')
local Url = require('jls.net.Url')
local HttpMessage = require('jls.net.http.HttpMessage')
local HeaderStreamHandler = require('jls.net.http.HeaderStreamHandler')
local strings = require('jls.util.strings')

--[[
The presence of a message body in a response depends on both the
request method to which it is responding and the response status code.
Responses to the HEAD request method never include a message body
because the associated response header fields (e.g., Transfer-Encoding,
Content-Length, etc.), if present, indicate only what their values
would have been if the request method had been GET.

3.  If a Transfer-Encoding header field is present and the chunked
  transfer coding is the final encoding, the message body length
  is determined by reading and decoding the chunked data until the
  transfer coding indicates the data is complete.
  If a message is received with both a Transfer-Encoding and a
  Content-Length header field, the Transfer-Encoding overrides the
  Content-Length.
5.  If a valid Content-Length header field is present without
  Transfer-Encoding, its decimal value defines the expected message
  body length in octets.
6.  If this is a request message and none of the above are true, then
  the message body length is zero (no message body is present).
7.  Otherwise, this is a response message without a declared message
  body length, so the message body length is determined by the
  number of octets received prior to the server closing the
  connection.
]]--

local function sendRequest(tcpClient, request)
  logger:finer('sendRequest()')
  request:applyBodyLength()
  return request:writeHeaders(tcpClient):next(function()
    logger:finer('sendRequest() writeHeaders() done')
    return request:writeBody(tcpClient)
  end)
end

local getSecure = require('jls.lang.loader').singleRequirer('jls.net.secure')

local function newTcpClient(isSecure)
  local tcpClient
  if isSecure and getSecure() then
    tcpClient = getSecure().TcpSocket:new()
    --tcpClient.sslCheckHost = options.checkHost == true
  else
    tcpClient = TcpSocket:new()
  end
  return tcpClient
end

local function getHostHeader(host, port)
  if port then
    return host..':'..tostring(port)
  end
  return host
end

local function isUrlSecure(url)
  return url:getProtocol() == 'https' or url:getProtocol() == 'wss'
end

local function sameClient(url1, url2)
  return url1:getHost() == url2:getHost() and url1:getPort() == url2:getPort() and isUrlSecure(url1) == isUrlSecure(url2)
end

--[[--
The HttpClient class enables to send an HTTP request.
@usage
local event = require('jls.lang.event')
local HttpClient = require('jls.net.http.HttpClient')
local httpClient = HttpClient:new({
  url = 'https://www.openssl.org/',
  method = 'GET',
  headers = {}
})
httpClient:connect():next(function()
  return httpClient:sendReceive()
end):next(function(response)
  print('status code is', response:getStatusCode())
  print(response:getBody())
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
  -- @tparam[opt] string options.target The request target path.
  -- @tparam[opt] string options.method The HTTP method, default is GET.
  -- @tparam[opt] table options.headers The HTTP request headers.
  -- @tparam[opt] string options.body The HTTP request body, default is empty body.
  -- @tparam[opt] boolean options.followRedirect true to follow redirections.
  -- @tparam[opt] number options.maxRedirectCount The maximum of redirections, default is 3.
  -- @return a new HTTP client
  function httpClient:initialize(options)
    logger:finer('httpClient:initialize(...)')
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

  function httpClient:getTcpClient()
    return self.tcpClient
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

  function httpClient:reconnect()
    logger:finer('httpClient:reconnect()')
    self:closeClient(false)
    local request = self.request
    local url = request.url
    local isSecure = isUrlSecure(url)
    local host = url:getHost()
    local port = url:getPort()
    self.tcpClient = newTcpClient(isSecure)
    if self.proxyHost then
      if isSecure then
        local connectTcp = newTcpClient(false)
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
    self.request:close()
    if self.response then
      self.response:close()
    end
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
  function httpClient:close()
    self:closeRequest()
    return self:closeClient()
  end

  function httpClient:getRequest()
    return self.request
  end

  function httpClient:getResponse()
    return self.response
  end

  function httpClient:processResponseHeaders()
  end

  --- Connects this HTTP client if not already connected.
  -- @treturn jls.lang.Promise a promise that resolves once this client is connected.
  function httpClient:connect()
    logger:finer('httpClient:connect()')
    if self.tcpClient then
      return Promise.resolve(self)
    end
    return self:reconnect()
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
        logger:fine('httpClient:receiveResponseHeaders() header done, status code is %d, remainingBuffer is #%s',
          response:getStatusCode(), remainingBuffer and #remainingBuffer)
      end
      if self.maxRedirectCount > 0 and (response:getStatusCode() // 100) == 3 then
        local location = response:getHeader(HttpMessage.CONST.HEADER_LOCATION)
        if location then
          logger:fine('httpClient:receiveResponseHeaders() redirected #%d to "%s"', self.maxRedirectCount, location)
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

end)
