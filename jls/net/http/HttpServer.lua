--- An HTTP server implementation that handles HTTP requests.
-- @module jls.net.http.HttpServer
-- @pragma nostrip

local logger = require('jls.lang.logger')
local TcpServer = require('jls.net.TcpServer')
local HttpExchange = require('jls.net.http.HttpExchange')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local HeaderStreamHandler = require('jls.net.http.HeaderStreamHandler')
local List = require('jls.util.List')
local HttpContext = require('jls.net.http.HttpContext')
local HttpFilter = require('jls.net.http.HttpFilter')

local function requestToString(exchange)
  local request = exchange:getRequest()
  if request then
    local hostport = request:getHeader(HTTP_CONST.HEADER_HOST)
    local path = request:getTargetPath()
    return request:getMethod()..' '..tostring(path)..' '..tostring(hostport)
  end
  return '?'
end

local function compareByIndex(a, b)
  return a:getIndex() > b:getIndex()
end

--[[-- An HTTP server.
The basic HTTP 1.1 server implementation.
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
return require('jls.lang.class').create(function(httpServer)

  --- Creates a new HTTP server.
  -- @function HttpServer:new
  -- @return a new HTTP server
  function httpServer:initialize(tcp)
    self.contexts = {}
    self.filters = {}
    self.parentContextHolder = nil
    self.notFoundContext = HttpContext:new('not found', HttpContext.notFoundHandler)
    self.tcpServer = tcp or TcpServer:new()
    self.tcpServer.onAccept = function(_, client)
      self:onAccept(client)
    end
    self.pendings = {}
  end

  --- Creates a @{jls.net.http.HttpContext|context} in this server with the specified path and using the specified handler.
  -- The path is a Lua pattern that match the full path, take care of escaping the magic characters ^$()%.[]*+-?.
  -- You could use the @{jls.util.strings}.escape() function.
  -- The path is absolute and starts with a slash '/'.
  -- @tparam string path The path of the context.
  -- @param handler The @{jls.net.http.HttpHandler|handler} or a handler function.
  --   The function takes one argument which is the @{HttpExchange} and will be called when the body is available.
  -- @return the new context
  function httpServer:createContext(path, handler, ...)
    if type(path) ~= 'string' then
      error('Invalid context path "'..tostring(path)..'"')
    end
    return self:addContext(HttpContext:new(path, handler, ...))
  end

  function httpServer:addContext(context)
    table.insert(self.contexts, context)
    table.sort(self.contexts, compareByIndex)
    return context
  end

  --- Adds the specified contexts.
  -- It could be a mix of contexts or pair of path, handler to create.
  -- @tparam table contexts The contexts to add.
  -- @return the new context
  function httpServer:addContexts(contexts)
    for _, context in ipairs(contexts) do
      if HttpContext:isInstance(context) then
        self:addContext(context)
      end
    end
    for path, handler in pairs(contexts) do
      if type(path) == 'string' then
        self:createContext(path, handler)
      end
    end
    return self
  end

  function httpServer:removeContext(pathOrContext)
    if type(pathOrContext) == 'string' then
      local context = self:getContext(pathOrContext)
      if context then
        List.removeFirst(self.contexts, context)
      end
    elseif HttpContext:isInstance(pathOrContext) then
      List.removeAll(self.contexts, pathOrContext)
    end
  end

  function httpServer:removeAllContexts()
    self.contexts = {}
  end

  function httpServer:addFilter(filter)
    if type(filter) == 'function' then
      filter = HttpFilter:new(filter)
    elseif not HttpFilter:isInstance(filter) then
      error('Invalid filter argument, type is '..type(filter))
    end
    table.insert(self.filters, filter)
    return filter
  end

  function httpServer:removeFilter(filter)
    List.removeAll(self.filters, filter)
  end

  function httpServer:removeAllFilters()
    self.filters = {}
  end

  function httpServer:getFilters()
    return self.filters
  end

  function httpServer:getParentContextHolder()
    return self.parentContextHolder
  end

  function httpServer:setParentContextHolder(parent)
    self.parentContextHolder = parent
    return self
  end

  function httpServer:getContext(path)
    for _, context in ipairs(self.contexts) do
      if context:getPath() == path then
        return context
      end
    end
    return nil
  end

  function httpServer:findContext(path, request)
    for _, context in ipairs(self.contexts) do
      if context:matchRequest(path, request) then
        return context
      end
    end
    return nil
  end

  function httpServer:getMatchingContext(path, request)
    local context = self:findContext(path, request)
    if not context then
      if self.parentContextHolder then
        context = self.parentContextHolder:findContext(path, request) or self.notFoundContext
      else
        context = self.notFoundContext
      end
    end
    if logger:isLoggable(logger.FINER) then
      logger:finer('httpServer:getMatchingContext("'..path..'") => "'..context:getPath()..'"')
    end
    return context
  end

  function httpServer:closeContexts()
    for _, context in ipairs(self.contexts) do
      context:close()
    end
  end

  -- TODO Remove
  function httpServer:toHandler()
    return function(httpExchange)
      local request = httpExchange:getRequest()
      local context = self:getMatchingContext(request:getTargetPath())
      return httpExchange:handleRequest(context)
    end
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
    if self.keepAlive then
      client:setKeepAlive(true, self.keepAlive)
    end
    local exchange = HttpExchange:new(client)
    local keepAlive = false
    local remainingBuffer = nil
    local requestHeadersPromise = nil
    local hsh = HeaderStreamHandler:new(exchange:getRequest())
    -- TODO limit headers
    exchange:setAttribute('start_time', os.time())
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
      if logger:isLoggable(logger.FINE) then
        logger:fine('httpServer:onAccept() response body '..requestToString(exchange)..' done '..tostring(exchange:getResponse():getStatusCode()))
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

  function httpServer:closePendings(delaySec)
    local time = os.time() - (delaySec or 0)
    local count = 0
    for client, exchange in pairs(self.pendings) do
      local start_time = exchange:getAttribute('start_time')
      if type(start_time) ~= 'number' or start_time < time then
        exchange:close()
        client:close()
        self.pendings[client] = nil
        count = count + 1
      end
    end
    if logger:isLoggable(logger.FINE) then
      logger:fine('httpServer:closePendings('..tostring(delaySec)..') '..tostring(count)..' pending request(s) closed')
    end
    return count
  end

  --- Closes this server.
  -- @tparam[opt] function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the server is closed.
  function httpServer:close(callback)
    local p = self.tcpServer:close(callback)
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
    return p
  end
end, function(HttpServer)

  require('jls.lang.loader').lazyMethod(HttpServer, 'createSecure', function(secure, class)
    if not secure then
      return function()
        return nil, 'Not available'
      end
    end

    local HandshakeExchange = class.create('jls.net.http.Attributes', function(handshakeExchange)
      handshakeExchange.close = class.emptyFunction
    end)
    local SecureTcpServer = class.create(secure.TcpServer, function(secureTcpServer)
      function secureTcpServer:onHandshakeStarting(client)
        if self._hss then
          local exchange = HandshakeExchange:new()
          exchange:setAttribute('start_time', os.time())
          self._hss.pendings[client] = exchange
        end
      end
      function secureTcpServer:onHandshakeCompleted(client)
        if self._hss then
          self._hss.pendings[client] = nil
        end
      end
    end)

    return function(secureContext)
      local tcp = SecureTcpServer:new()
      if type(secureContext) == 'table' then
        tcp:setSecureContext(secure.Context:new(secureContext))
      end
      local httpsServer = HttpServer:new(tcp)
      tcp._hss = httpsServer
      return httpsServer
    end
  end, 'jls.net.secure', 'jls.lang.class')

end)
