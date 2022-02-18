--- An HTTP server implementation that handles HTTP requests.
-- @module jls.net.http.HttpServer
-- @pragma nostrip

local logger = require('jls.lang.logger')
local TcpServer = require('jls.net.TcpServer')
local HttpExchange = require('jls.net.http.HttpExchange')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local HeaderStreamHandler = require('jls.net.http.HeaderStreamHandler')

local function requestToString(exchange)
  local request = exchange:getRequest()
  if request then
    local hostport = request:getHeader(HTTP_CONST.HEADER_HOST)
    local path = request:getTargetPath()
    return request:getMethod()..' '..tostring(path)..' '..tostring(hostport)
  end
  return '?'
end

--[[-- An HTTP server.
The HttpServer inherits from @{HttpContextHolder}.
@usage
local event = require('jls.lang.event')
local HttpServer = require('jls.net.http.HttpServer')
local hostname, port = '::', 3001
local httpServer = HttpServer:new()
httpServer:bind(hostname, port):next(function()
  print('Server bound to "'..hostname..'" on port '..tostring(port))
end, function(err) -- could failed if address is in use or hostname cannot be resolved
  print('Cannot bind HTTP server, '..tostring(err))
end)
httpServer:createContext('/', function(httpExchange)
  local response = httpExchange:getResponse()
  response:setBody('It works !')
end)
event:loop()
@type HttpServer
]]
return require('jls.lang.class').create('jls.net.http.HttpContextHolder', function(httpServer, super)

  --- Creates a new HTTP server.
  -- @function HttpServer:new
  -- @return a new HTTP server
  function httpServer:initialize(tcp)
    super.initialize(self)
    self.tcpServer = tcp or TcpServer:new()
    self.tcpServer.onAccept = function(_, client)
      self:onAccept(client)
    end
    self.pendings = {}
  end

  function httpServer:preFilter(exchange)
    for _, filter in ipairs(self:getFilters()) do
      if filter:doFilter(exchange) == false then
        return false
      end
    end
    return true
  end

  --[[
    The presence of a message body in a request is signaled by a
  Content-Length or Transfer-Encoding header field.  Request message
  framing is independent of method semantics, even if the method does
  not define any use for a message body
  ]]
  function httpServer:onAccept(client, buffer)
    logger:finer('httpServer:onAccept()')
    local exchange = HttpExchange:new(client)
    local keepAlive = false
    local remainingBuffer = nil
    local requestHeadersPromise = nil
    local hsh = HeaderStreamHandler:new(exchange:getRequest())
    -- TODO limit headers
    self.pendings[client] = exchange
    hsh:read(client, buffer):next(function(remainingHeaderBuffer)
      logger:finer('httpServer:onAccept() header read')
      self.pendings[client] = nil
      local request = exchange:getRequest()
      if self:preFilter(exchange) then
        local path = request:getTargetPath()
        local context = self:getMatchingContext(path, request)
        requestHeadersPromise = exchange:handleRequest(context)
      end
      logger:finer('httpServer:onAccept() request headers processed')
      return request:readBody(client, remainingHeaderBuffer)
    end):next(function(remainingBodyBuffer)
      logger:finer('httpServer:onAccept() body done')
      exchange:notifyRequestBody()
      remainingBuffer = remainingBodyBuffer
      if requestHeadersPromise then
        return requestHeadersPromise
      end
    end):next(function()
      if logger:isLoggable(logger.FINER) then
        logger:finer('httpServer:onAccept() request '..requestToString(exchange)..' processed')
      end
      keepAlive = exchange:applyKeepAlive()
      exchange:prepareResponseHeaders()
      return exchange:getResponse():writeHeaders(client)
    end):next(function()
      if logger:isLoggable(logger.FINER) then
        logger:finer('httpServer:onAccept() response headers '..requestToString(exchange)..' done')
      end
      -- post filter
      --exchange:prepareResponseBody()
      return exchange:getResponse():writeBody(client)
    end):next(function()
      if logger:isLoggable(logger.FINER) then
        logger:finer('httpServer:onAccept() response body '..requestToString(exchange)..' done')
      end
      if keepAlive and not self.tcpServer:isClosed() then
        local c = exchange:removeClient()
        if c then
          logger:finer('httpServer:onAccept() keeping client alive')
          exchange:close()
          return self:onAccept(c, remainingBuffer)
        end
      end
      exchange:close()
    end, function(err)
      if not hsh:isEmpty() then
        if logger:isLoggable(logger.FINE) then
          logger:fine('httpServer:onAccept() read header error "'..tostring(err)..'" on '..requestToString(exchange))
        end
        if hsh:getErrorStatus() and not client:isClosed() then
          HttpExchange.response(exchange, hsh:getErrorStatus())
          exchange:getResponse():writeHeaders(client)
        end
      end
      exchange:close()
    end)
  end

  --- Binds this server to the specified address and port number.
  -- @tparam[opt] string node the address, the address could be an IP address or a host name.
  -- @tparam[opt] number port the port number, 0 to let the system automatically choose a port, default is 80.
  -- @tparam[opt] number backlog the accept queue size, default is 32.
  -- @tparam[opt] function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the server is bound.
  -- @usage
  --local s = HttpServer:new()
  --s:bind('127.0.0.1', 80)
  function httpServer:bind(node, port, backlog, callback)
    return self.tcpServer:bind(node or '::', port or 80, backlog, callback)
  end

  function httpServer:getAddress()
    return self.tcpServer:getLocalName()
  end
  --- Closes this server.
  -- @tparam[opt] function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the server is closed.
  function httpServer:close(callback)
    local pendings = self.pendings
    self.pendings = {}
    local count = 0
    for client, exchange in pairs(pendings) do
      exchange:close()
      client:close()
      count = count + 1
    end
    if logger:isLoggable(logger.FINE) then
      logger:fine('httpServer:close() '..tostring(count)..' pending request(s) closed')
    end
    self:closeContexts()
    return self.tcpServer:close(callback)
  end
end, function(HttpServer)

  local getSecure = require('jls.lang.loader').singleRequirer('jls.net.secure')

  function HttpServer.createSecure(secureContext)
    local secure = getSecure()
    if secure then
      local tcp = secure.TcpServer:new()
      if type(secureContext) == 'table' then
        tcp:setSecureContext(secure.Context:new(secureContext))
      end
      return HttpServer:new(tcp), tcp
    end
  end

end)
