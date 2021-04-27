--- An HTTP client implementation that enable to send @{jls.net.http.HttpRequest|request} and receive @{jls.net.http.HttpResponse|response}.
-- @module jls.net.http.HttpClient
-- @pragma nostrip

local logger = require('jls.lang.logger')
local TcpClient = require('jls.net.TcpClient')
local URL = require('jls.net.URL')
local HttpMessage = require('jls.net.http.HttpMessage')
local HttpRequest = require('jls.net.http.HttpRequest')
local HttpResponse = require('jls.net.http.HttpResponse')
local HeaderStreamHandler = require('jls.net.http.HeaderStreamHandler')
local readBody = require('jls.net.http.readBody')

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
return require('jls.lang.class').create(function(httpClient)

  local getSecure = require('jls.lang.loader').singleRequirer('jls.net.secure')

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
    local method = options.method or 'GET'
    local request = HttpRequest:new()
    self.isSecure = false
    self.maxRedirectCount = 0
    self.request = request
    if type(options.headers) == 'table' then
      request:setHeadersTable(options.headers)
    end
    request:setMethod(method)
    if type(options.url) == 'string' then
      self:setUrl(options.url)
    end
    if type(options.target) == 'string' then
      request:setTarget(options.target)
    end
    if type(options.host) == 'string' then
      self.host = options.host
    end
    if type(options.port) == 'number' then
      self.port = options.port
    end
    if options.followRedirect == true then
      self.maxRedirectCount = 3
    end
    if type(options.maxRedirectCount) == 'number' then
      self.maxRedirectCount = options.maxRedirectCount
    end
    if options.response and HttpResponse:isInstance(options.response) then
      self.response = options.response
    else
      self.response = HttpResponse:new()
      self.response:bufferBody()
    end
    if options.body then
      request:setBody(options.body)
    end
    if self.host then
      local hostHeader = self.host
      if self.port then
        hostHeader = hostHeader..':'..tostring(self.port)
      end
      request:setHeader(HttpMessage.CONST.HEADER_HOST, hostHeader)
    end
    -- add accept headers
    self:initializeTcpClient()
  end

  function httpClient:initializeTcpClient()
    if self.isSecure and getSecure() then
      self.tcpClient = getSecure().TcpClient:new()
      --self.tcpClient.sslCheckHost = options.checkHost == true
    else
      self.tcpClient = TcpClient:new()
    end
  end

  function httpClient:getTcpClient()
    return self.tcpClient
  end

  function httpClient:setUrl(url)
    if logger:isLoggable(logger.FINER) then
      logger:finer('httpClient:setUrl('..tostring(url)..')')
    end
    if self.tcpClient then
      error('already initialized')
    end
    local u = URL:new(url)
    local target = u:getFile()
    self.isSecure = u:getProtocol() == 'https' or u:getProtocol() == 'wss'
    self.host = u:getHost()
    self.port = u:getPort()
    self.request:setTarget(target or '/')
  end

  --- Connects this HTTP client.
  -- @treturn jls.lang.Promise a promise that resolves once this client is connected.
  function httpClient:connect()
    logger:finer('httpClient:connect()')
    return self.tcpClient:connect(self.host or 'localhost', self.port or 80):next(function()
      return self
    end)
  end

  function httpClient:closeClient()
    local tcpClient = self.tcpClient
    self.tcpClient = nil
    return tcpClient:close()
  end

  --- Closes this HTTP client.
  -- @treturn jls.lang.Promise a promise that resolves once the client is closed.
  function httpClient:close()
    if self.request then
      self.request:close()
      self.request = nil
    end
    if self.response then
      self.response:close()
      self.response = nil
    end
    return self:closeClient()
  end

  function httpClient:getRequest()
    return self.request
  end

  function httpClient:processResponseHeaders()
  end

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

  function httpClient:receiveResponse()
    logger:finer('httpClient:receiveResponse()')
    local response = HttpResponse:new()
    local hsh = HeaderStreamHandler:new(response)
    return hsh:read(self.tcpClient):next(function(buffer)
      if logger:isLoggable(logger.FINE) then
        logger:fine('httpClient:receiveResponse() header done, status code is '..tostring(response:getStatusCode()))
      end
      if self.maxRedirectCount > 0 and (response:getStatusCode() // 100) == 3 then
        local location = response:getHeader(HttpMessage.CONST.HEADER_LOCATION)
        if location then
          if logger:isLoggable(logger.FINE) then
            logger:fine('httpClient:receiveResponse() redirected #'..tostring(self.maxRedirectCount)..' to "'..tostring(location)..'"')
          end
          self.maxRedirectCount = self.maxRedirectCount - 1
          return self:closeClient():next(function()
            self:setUrl(location)
            self:initializeTcpClient()
            return self:connect()
          end):next(function()
            return sendRequest(self.tcpClient, self.request)
          end):next(function()
            return self:receiveResponse()
          end)
        end
      end
      self.response:setLine(response:getLine())
      self.response:setHeadersTable(response:getHeadersTable())
      self:processResponseHeaders()
      return readBody(self.response, self.tcpClient, buffer)
    end):next(function(remainingBuffer)
      logger:fine('httpClient:receiveResponse() body done')
      return self.response
    end)
  end

  --- Sends the request then receives the response.
  -- @treturn jls.lang.Promise a promise that resolves to the @{HttpResponse} received.
  function httpClient:sendReceive()
    logger:finer('httpClient:sendReceive()')
    return sendRequest(self.tcpClient, self.request):next(function()
      logger:finer('httpClient:sendReceive() send completed')
      return self:receiveResponse()
    end)
  end

end)
