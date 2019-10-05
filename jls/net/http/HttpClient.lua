--- An HTTP client implementation that enable to send @{HttpRequest} and receive @{HttpResponse}.
-- @module jls.net.http.HttpClient
-- @pragma nostrip

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local net = require('jls.net')
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
  -- @return a new HTTP client
  function httpClient:initialize(options)
    logger:finer('httpClient:initialize(...)')
    options = options or {}
    local method = options.method or 'GET'
    local request = HttpRequest:new()
    self.isSecure = false
    self.request = request
    if type(options.headers) == 'table' then
      request:setHeaders(options.headers)
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
    if type(options.body) == 'string' then
      request:setContentLength(#options.body)
      request:setBody(options.body)
    end
    if self.host then
      request:setHeader(HttpMessage.CONST.HEADER_HOST, self.host)
    end
    -- add accept headers
    if options.tcpClient then
      self.tcpClient = options.tcpClient
    elseif self.isSecure and getSecure() then
      self.tcpClient = getSecure().TcpClient:new()
      --self.tcpClient.sslCheckHost = options.checkHost == true
    else
      self.tcpClient = net.TcpClient:new()
    end
  end

  function httpClient:setUrl(url)
    logger:finer('httpClient:setUrl('..tostring(url)..')')
    local u = URL:new(url)
    local target = u:getFile()
    self.isSecure = u:getProtocol() == 'https' or u:getProtocol() == 'wss'
    self.host = u:getHost()
    self.port = u:getPort()
    self.request:setTarget(target or '/')
  end

  --- Connects this HTTP client.
  -- @return true in case of success
  function httpClient:connect(callback)
    logger:finer('httpClient:connect()')
    return self.tcpClient:connect(self.host or 'localhost', self.port or 80, callback)
  end

  --- Closes this HTTP client.
  -- @tparam function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the client is closed.
  function httpClient:close(callback)
    return self.tcpClient:close(callback)
  end

  --- Returns the HTTP message request.
  -- @return the HTTP message request.
  function httpClient:getRequest()
    return self.request
  end

  --- Returns the HTTP message response.
  -- @return the HTTP message response.
  function httpClient:getResponse()
    return self.response
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

  --- Sends the request then receives the response.
  -- @return a promise that resolves once the response is received.
  function httpClient:sendReceive()
    logger:finer('httpClient:sendReceive()')
    local promise, resolve, reject = Promise.createWithCallbacks()
    local client = self
    local response = HttpResponse:new()
    self.request:writeHeaders(client.tcpClient):next(function()
      logger:finer('httpClient:sendReceive() writeHeaders() done')
      return client.request:writeBody(client.tcpClient)
    end):next(function()
      logger:finer('httpClient:sendReceive() writeBody() done')
      local hsh = HeaderStreamHandler:new(response)
      return hsh:read(client.tcpClient)
    end):next(function(buffer)
      logger:fine('httpClient:sendReceive() header done')
      return readBody(response, client.tcpClient, buffer)
    end):next(function()
      logger:fine('httpClient:sendReceive() body done')
      -- TODO We may want to handle redirections, status code 3xx
      resolve(response)
    end, function(err)
      if logger:isLoggable(logger.FINE) then
        logger:fine('httpClient:sendReceive() error "'..tostring(err)..'"')
      end
      reject(err or 'Unknown error')
    end)
    return promise
  end
end)
