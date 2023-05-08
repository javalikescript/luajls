--- An HTTP server implementation that handles HTTP requests.
-- @module jls.net.http.HttpServer
-- @pragma nostrip

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local TcpSocket = require('jls.net.TcpSocket')
local HttpExchange = require('jls.net.http.HttpExchange')
local HttpMessage = require('jls.net.http.HttpMessage')
local HttpHandler = require('jls.net.http.HttpHandler')
local HeaderStreamHandler = require('jls.net.http.HeaderStreamHandler')
local HttpFilter = require('jls.net.http.HttpFilter')
local List = require('jls.util.List')

local HTTP_CONST = HttpMessage.CONST

local function requestToString(exchange)
  local request = exchange:getRequest()
  if request then
    local hostport = request:getHeader(HTTP_CONST.HEADER_HOST)
    local path = request:getTargetPath()
    return request:getMethod()..' '..tostring(path)..' '..tostring(hostport)..' '..request:getVersion()
  end
  return '?'
end

local function compareByIndex(a, b)
  return a:getIndex() > b:getIndex()
end

local notFoundHandler = HttpHandler:new(function(self, exchange)
  local response = exchange:getResponse()
  response:setStatusCode(HttpMessage.CONST.HTTP_NOT_FOUND, 'Not Found')
  response:setBody('<p>The resource "'..exchange:getRequest():getTarget()..'" is not available.</p>')
end)

local HttpContext

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
httpServer:createContext('/', function(exchange)
  local response = exchange:getResponse()
  response:setBody('It works !')
end)
event:loop()
@type HttpServer
]]
local HttpServer = class.create(function(httpServer)

  --- Creates a new HTTP server.
  -- @function HttpServer:new
  -- @return a new HTTP server
  function httpServer:initialize(tcp)
    self.contexts = {}
    self.filters = {}
    self.parent = nil
    self.notFoundContext = HttpContext:new('not found', notFoundHandler)
    self.tcpServer = tcp or TcpSocket:new()
    self.tcpServer.onAccept = function(_, client)
      self:onAccept(client)
    end
    self.pendings = {}
  end

  --- Creates a context in this server with the specified path and using the specified handler.
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

  function httpServer:prepareResponseHeaders(exchange)
    local response = exchange:getResponse()
    response:setHeader(HttpMessage.CONST.HEADER_SERVER, HttpMessage.CONST.DEFAULT_SERVER)
    exchange:prepareResponseHeaders()
  end

  -- TODO remove
  function httpServer:getParentContextHolder()
    return self.parent
  end

  -- TODO remove
  function httpServer:setParentContextHolder(parent)
    logger:warn('this method is deprecated, please use setParent')
    self.parent = parent
    return self
  end

  function httpServer:setParent(parent)
    self.parent = parent
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
      if self.parent then
        context = self.parent:findContext(path, request) or self.notFoundContext
      else
        context = self.notFoundContext
      end
    end
    if logger:isLoggable(logger.FINER) then
      logger:finer('httpServer:getMatchingContext("'..path..'") => "'..context:getPath()..'"')
    end
    return context
  end

  -- TODO Remove
  function httpServer:toHandler()
    return function(exchange)
      local request = exchange:getRequest()
      local context = self:getMatchingContext(request:getTargetPath())
      return exchange:handleRequest(context)
    end
  end

  function httpServer:preFilter(exchange)
    for _, filter in ipairs(self.filters) do
      if filter:doFilter(exchange) == false then
        return false
      end
    end
    if self.parent then
      return self.parent:preFilter(exchange)
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
      if logger:isLoggable(logger.FINER) then
        logger:finer('httpServer:onAccept() request headers '..requestToString(exchange)..' processed')
        logger:finer(request:getRawHeaders())
      end
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
      self:prepareResponseHeaders(exchange)
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
  -- This method will close the pending client connections and contexts.
  -- @tparam[opt] function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the server is closed.
  function httpServer:close(callback)
    local cb, d = Promise.ensureCallback(callback)
    self.tcpServer:close(function(err)
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
      local contexts = self.contexts
      self.contexts = {}
      for _, context in ipairs(contexts) do
        context:close()
      end
      local filters = self.filters
      self.filters = {}
      for _, filter in ipairs(filters) do
        filter:close()
      end
      if cb then
        cb(err)
      end
    end)
    return d
  end

end, function(HttpServer)

  --- The default not found handler.
  HttpServer.notFoundHandler = notFoundHandler

  require('jls.lang.loader').lazyMethod(HttpServer, 'createSecure', function(secure, class)
    if not secure then
      return function()
        return nil, 'Not available'
      end
    end

    local SecureTcpServer = class.create(secure.TcpSocket, function(secureTcpServer)
      function secureTcpServer:onHandshakeStarting(client)
        if self._hss then
          local exchange = HttpExchange:new()
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

--- The HttpContext class maps a path to a handler.
-- The HttpContext is used by the @{HttpServer}.
-- @type HttpContext
HttpContext = class.create(function(httpContext, _, HttpContext)

  --- Creates a new Context.
  -- The handler will be called when the request headers have been received if specified.
  -- The handler will be called when the body has been received if no response has been set.
  -- @tparam string path the context path
  -- @tparam[opt] function handler the context handler
  --   the function takes one argument which is an @{HttpExchange}.
  -- @function HttpContext:new
  function httpContext:initialize(path, handler)
    if type(path) == 'string' then
      self.pattern = '^'..path..'$'
    else
      error('Invalid context path, type is '..type(path))
    end
    self.repl = '%1'
    --self.index = string.len(path)
    self.index = string.len(string.gsub(string.gsub(path, '%%.', '_'), '%([^%)]+%)', ''))
    self:setHandler(handler or notFoundHandler)
  end

  function httpContext:getHandler()
    return self.handler
  end

  function httpContext:setHandler(handler)
    if type(handler) == 'function' then
      self.handler = HttpHandler.onBodyHandler(handler)
    elseif HttpHandler:isInstance(handler) then
      self.handler = handler
    elseif type(handler) == 'table' and type(handler.handle) == 'function' then
      self.handler = handler
    else
      error('Invalid context handler, type is '..type(handler))
    end
    return self
  end

  --- Returns the context path.
  -- @treturn string the context path.
  function httpContext:getPath()
    return string.sub(self.pattern, 2, -2)
  end

  function httpContext:getPathReplacement()
    return self.repl
  end

  --- Sets the path replacement, default is '%1'.
  -- @param repl the replacement compliant with the string.gsub function
  -- @return this context
  function httpContext:setPathReplacement(repl)
    self.repl = repl
    return self
  end

  function httpContext:setIndex(index)
    self.index = index
    return self
  end

  function httpContext:getIndex()
    return self.index
  end

  --- Returns the captured values of the specified path.
  -- @treturn string the first captured value, nil if there is no captured value.
  function httpContext:getArguments(path)
    return string.match(path, self.pattern)
  end

  --- Returns the target path of the specified path.
  -- It consists in the first captured value, or the 
  -- @treturn string the first captured value, nil if there is no captured value.
  function httpContext:replacePath(path)
    return string.gsub(path, self.pattern, self.repl)
  end

  function httpContext:matchRequest(path)
    if string.match(path, self.pattern) then
      return true
    end
    return false
  end

  function httpContext:handleExchange(exchange)
    return self.handler:handle(exchange)
  end

  function httpContext:copyContext()
    return HttpContext:new(self:getPath(), self:getHandler()):setPathReplacement(self:getPathReplacement())
  end

  function httpContext:close()
    if type(self.handler.close) == 'function' then
      self.handler:close()
    end
  end

  HttpContext.notFoundHandler = notFoundHandler

end)

--- The HttpContext class.
HttpServer.HttpContext = HttpContext

return HttpServer
