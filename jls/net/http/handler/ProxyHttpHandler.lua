--- Provide a simple HTTP handler that forward requests.
-- @module jls.net.http.handler.ProxyHttpHandler
-- @pragma nostrip

local logger = require('jls.lang.logger')
local HttpClient = require('jls.net.http.HttpClient')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local HttpExchange = require('jls.net.http.HttpExchange')
local DelayedStreamHandler = require('jls.io.streams.DelayedStreamHandler')
local Promise = require('jls.lang.Promise')

--- A ProxyHttpHandler class.
-- @type ProxyHttpHandler
return require('jls.lang.class').create('jls.net.http.HttpHandler', function(proxyHttpHandler, super)

  --- Creates a proxy @{HttpHandler}.
  -- @tparam[opt] string baseUrl the base URL to proxy to.
  function proxyHttpHandler:initialize(baseUrl)
    if baseUrl then
      self.baseUrl = string.gsub(baseUrl, '/+$', '')
    end
    self.protocol = 'http'
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
    local baseUrl = self:getBaseUrl(httpExchange)
    if baseUrl then
      local path = httpExchange:getRequestArguments()
      if path then
        return baseUrl..string.gsub(path, '^/*', '/')
      end
    end
    return nil
  end

  function proxyHttpHandler:handle(httpExchange)
    if not HttpExchange.methodAllowed(httpExchange, {HTTP_CONST.METHOD_GET, HTTP_CONST.METHOD_HEAD}) then
      return
    end
    local request = httpExchange:getRequest()
    local response = httpExchange:getResponse()
    local targetUrl = self:getTargetUrl(httpExchange)
    if not targetUrl then
      httpExchange:setResponseStatusCode(HTTP_CONST.HTTP_FORBIDDEN, 'Forbidden', '<p>The server cannot proxy your request to the specified host.</p>')
      return
    end
    if logger:isLoggable(logger.FINE) then
      logger:fine('proxyHttpHandler forward to "'..targetUrl..'"')
    end
    -- See https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Forwarded
    local client = HttpClient:new({
      url = targetUrl,
      method = request:getMethod(),
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
