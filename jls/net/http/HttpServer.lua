--- An HTTP server implementation that handles HTTP requests.
-- @module jls.net.http.HttpServer
-- @pragma nostrip

local class = require('jls.lang.class')
local logger = require('jls.lang.logger'):get(...)
local Promise = require('jls.lang.Promise')
local TcpSocket = require('jls.net.TcpSocket')
local HttpExchange = require('jls.net.http.HttpExchange')
local HttpMessage = require('jls.net.http.HttpMessage')
local HttpHandler = require('jls.net.http.HttpHandler')
local HeaderStreamHandler = require('jls.net.http.HeaderStreamHandler')
local HttpFilter = require('jls.net.http.HttpFilter')
local Http1 = require('jls.net.http.Http1')
local Http2 = require('jls.net.http.Http2')
local Url = require('jls.net.Url')
local List = require('jls.util.List')

local function compareByIndex(a, b)
  return a:getIndex() > b:getIndex()
end

local function computeIndex(pattern)
  local path = pattern
  local gsub = string.gsub
  path = gsub(path, '%[[^%]]+%]', '_') -- replace set by underscore
  path = gsub(path, '%%f.', '') -- remove frontier
  path = gsub(path, '%%b..', '') -- remove balanced
  path = gsub(path, '%%.', '_') -- replace escaped character by underscore
  path = gsub(path, '.[%*%-%?]', '') -- remove sequences
  path = gsub(path, '.%+', '_') -- remove +
  path = gsub(path, '[%(%)]', '') -- remove capture parenthesis
  return #path -- the index is the length of the path without pattern items and character classes
end

local notFoundHandler = HttpHandler:new(function(self, exchange)
  local response = exchange:getResponse()
  response:setStatusCode(HttpMessage.CONST.HTTP_NOT_FOUND, 'Not Found')
  response:setBody('<p>The resource "'..exchange:getRequest():getTarget()..'" is not available.</p>')
end)

local Stream = class.create(Http2.Stream, function(stream, super)

  function stream:onEndHeaders()
    super.onEndHeaders(self)
    local http2 = self.http2
    logger:finer('stream:onEndHeaders() id: %s', self.id)
    if http2.start_time then
      http2.start_time = nil
    end
    local request = self.message
    local exchange = self.exchange
    local promise, cb = Promise.withCallback()
    request.consume = function()
      return promise
    end
    self.endStreamCallback = cb
    local server = http2.server
    if server:preFilter(exchange) then
      local path = request:getTargetPath()
      local context = server:getMatchingContext(path, request)
      self.handling = exchange:handleRequest(context)
    end
  end

  function stream:onEndStream()
    local exchange = self.exchange
    local endStreamCallback = self.endStreamCallback
    if endStreamCallback then
      self.endStreamCallback = nil
      endStreamCallback()
    end
    super.onEndStream(self)
    exchange:notifyRequestBody() -- TODO Remove
    self.http2.server:prepareResponseHeaders(exchange)
    local response = exchange:getResponse()
    local handling = self.handling
    self.handling = nil
    Promise.resolve(handling):next(function()
      return self:sendHeaders(response, true)
    end):next(function()
      self:sendBody(response)
    end):catch(function(reason)
      logger:warn('unable to reply due to "%s" on %s', reason, exchange)
    end)
  end

  function stream:clearCallbacks(reason)
    local endStreamCallback = self.endStreamCallback
    if endStreamCallback then
      self.endStreamCallback = nil
      logger:fine('clear end stream %d callback due to "%s"', self.id, reason)
      endStreamCallback(reason)
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

end)

local ServerHttp2 = class.create(Http2, function(http2, super)

  function http2:initialize(server, ...)
    super.initialize(self, ...)
    self.server = server
    self.start_time = os.time()
  end

  function http2:newStream(id)
    local exchange = HttpExchange:new()
    local stream = Stream:new(self, id, exchange.request)
    stream.exchange = exchange
    exchange.stream = stream
    logger:fine('ServerHttp2:newStream(%d)', id)
    return stream
  end

  function http2:closedStream(stream)
    super.closedStream(self, stream)
    if next(self.streams) == nil then
      self.start_time = os.time()
    end
  end

  function http2:doClose()
    super.doClose(self)
    self.server.pendings[self.client] = nil
  end

  function http2:onPing()
    if next(self.streams) == nil then
      self.start_time = os.time()
    end
  end

end)

local HttpContext

--[[-- An HTTP server.
The basic HTTP server implementation.
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
  -- @tparam string path The path of the context
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
    self:sortContexts()
    return context
  end

  function httpServer:sortContexts()
    table.sort(self.contexts, compareByIndex)
  end

  --- Adds the specified contexts.
  -- It could be a mix of contexts or pair of path, handler to create.
  -- @tparam table contexts The contexts to add
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
      logger:finer('getMatchingContext("%s") => "%s"', path, context:getPath())
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
    if self.parent and self.parent:preFilter(exchange) == false then
      return false
    end
    return HttpFilter.filter(exchange, self.filters)
  end

  function httpServer:onAccept(client)
    logger:finer('onAccept()')
    if client.sslGetAlpnSelected then -- secure
      if client:sslGetAlpnSelected() == 'h2' then -- HTTP/2
        self:handleHttp2Exchange(client)
        return
      end
    end
    self:handleExchange(client)
  end

  function httpServer:handleHttp2Exchange(client)
    logger:finer('handleHttp2Exchange()')
    local http2 = ServerHttp2:new(self, client, true)
    http2:readStart({
      [Http2.SETTINGS.MAX_CONCURRENT_STREAMS] = 100,
      [Http2.SETTINGS.ENABLE_CONNECT_PROTOCOL] = 1,
    }):next(function()
      logger:finer('handleHttp2Exchange() h2 read started')
      self.pendings[client] = http2
    end, function(reason)
      logger:warn('fail to start reading on h2 due to "%s"', reason)
      client:close()
    end)
  end

  --[[
    The presence of a message body in a request is signaled by a
  Content-Length or Transfer-Encoding header field.  Request message
  framing is independent of method semantics, even if the method does
  not define any use for a message body
  ]]
  function httpServer:handleExchange(client, buffer)
    logger:finer('handleExchange()')
    if self.keepAlive then
      client:setKeepAlive(true, self.keepAlive)
    end
    local exchange = HttpExchange:new()
    exchange.client = client
    local keepAlive = false
    local handling = nil
    local callback = nil
    local remnant = nil
    local hsh = HeaderStreamHandler:new(exchange:getRequest())
    -- TODO limit headers
    exchange.start_time = os.time()
    self.pendings[client] = exchange
    hsh:read(client, buffer):next(function(remnantBuffer)
      logger:finer('header read')
      self.pendings[client] = nil
      local request = exchange:getRequest()
      local promise
      promise, callback = Promise.withCallback()
      request.consume = function()
        return promise
      end
      if self:preFilter(exchange) then
        local path = request:getTargetPath()
        local context = self:getMatchingContext(path, request)
        handling = exchange:handleRequest(context)
      end
      logger:finer('request headers %s processed', exchange)
      if logger:isLoggable(logger.FINEST) then
        logger:finest('headers are %s', request:getRawHeaders())
      end
      return Http1.readBody(client, request, remnantBuffer)
    end):next(function(remnantBuffer)
      logger:finer('body done')
      callback()
      exchange:notifyRequestBody() -- TODO Remove
      remnant = remnantBuffer
      return handling
    end):next(function()
      logger:finer('request %s processed', exchange)
      keepAlive = exchange:applyKeepAlive()
      self:prepareResponseHeaders(exchange)
      return Http1.writeHeaders(client, exchange:getResponse())
    end):next(function()
      logger:finer('response headers %s done', exchange)
      -- post filter
      --exchange:prepareResponseBody()
      return Http1.writeBody(client, exchange:getResponse())
    end):next(function()
      logger:fine('response body %s done', exchange)
      if keepAlive and not self.tcpServer:isClosed() then
        local c = exchange.client
        exchange.client = nil
        if c then
          logger:finer('keeping client alive')
          exchange:close()
          return self:handleExchange(c, remnant)
        end
      end
      exchange:close()
    end, function(err)
      if not hsh:isEmpty() then
        logger:fine('read header error "%s" on %s', err, exchange)
        if hsh:getErrorStatus() and not client:isClosed() then
          HttpExchange.response(exchange, hsh:getErrorStatus())
          Http1.writeHeaders(client, exchange:getResponse())
        end
      end
      exchange:close()
    end)
  end

  --- Binds this server to the specified address and port number.
  -- @tparam[opt] string node the address, the address could be an IP address or a host name
  -- @tparam[opt] number port the port number, 0 to let the system automatically choose a port, default is 80
  -- @tparam[opt] number backlog the accept queue size, default is 32
  -- @tparam[opt] function callback an optional callback function to use in place of promise
  -- @treturn jls.lang.Promise a promise that resolves once the server is bound
  -- @usage
  --local s = HttpServer:new()
  --s:bind('127.0.0.1', 80)
  function httpServer:bind(node, port, backlog, callback)
    return self.tcpServer:bind(node or '::', port or 80, backlog, callback)
  end

  function httpServer:getAddress()
    return self.tcpServer:getLocalName()
  end

  local function closePending(client, closeable)
    if type(closeable.close) == 'function' then
      Promise.resolve(closeable:close()):next(function()
        client:close()
      end)
    else
      client:close()
    end
  end

  function httpServer:closePendings(delaySec)
    local time = os.time() - (delaySec or 0)
    local count = 0
    for client, closeable in pairs(self.pendings) do
      local start_time = closeable.start_time
      if type(start_time) ~= 'number' or start_time < time then
        self.pendings[client] = nil
        closePending(client, closeable)
        count = count + 1
      end
    end
    logger:fine('closePendings(%s) %s pending request(s) closed', delaySec, count)
    return count
  end

  --- Closes this server.
  -- This method will close the pending client connections and contexts.
  -- @tparam[opt] function callback an optional callback function to use in place of promise
  -- @treturn jls.lang.Promise a promise that resolves once the server is closed
  function httpServer:close(callback)
    local cb, d = Promise.ensureCallback(callback)
    self.tcpServer:close(function(err)
      local pendings = self.pendings
      self.pendings = {}
      local count = 0
      for client, closeable in pairs(pendings) do
        closePending(client, closeable)
        count = count + 1
      end
      logger:fine('close() %s pending request(s) closed', count)
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

  require('jls.lang.loader').lazyMethod(HttpServer, 'createSecure', function(secure)
    local SecureTcpSocket = class.create(secure.TcpSocket, function(secureTcpSocket)
      function secureTcpSocket:onHandshakeStarting(client)
        if self._hss then
          self._hss.pendings[client] = {
            start_time = os.time()
          }
        end
      end
      function secureTcpSocket:onHandshakeCompleted(client)
        if self._hss then
          self._hss.pendings[client] = nil
        end
      end
    end)
    return function(options)
      local tcp = SecureTcpSocket:new()
      if options then
        tcp:setSecureContext(class.asInstance(secure.Context, options))
      end
      local httpsServer = HttpServer:new(tcp)
      tcp._hss = httpsServer
      return httpsServer
    end
  end, 'jls.net.secure')

end)

--- The HttpContext class maps a path to a handler.
-- The HttpContext is used by the @{HttpServer}.
-- @type HttpContext
HttpContext = class.create(function(httpContext, _, HttpContext)

  --- Creates a new Context.
  -- The handler will be called when the request headers have been received if specified.
  -- The handler will be called when the body has been received if no response has been set.
  -- @tparam string path the context path
  -- @tparam[opt] function handler the context handler,
  --   the function takes one argument which is an @{HttpExchange}
  -- @function HttpContext:new
  function httpContext:initialize(path, handler)
    if type(path) == 'string' then
      self.pattern = '^'..path..'$'
    else
      error('Invalid context path, type is '..type(path))
    end
    self.repl = '%1'
    self.index = computeIndex(path)
    self:setHandler(handler or notFoundHandler)
    -- TODO Validate pattern to avoid late error
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
  -- @treturn string the context path
  function httpContext:getPath()
    return string.sub(self.pattern, 2, -2)
  end

  local function encodePercentChar(c)
    return string.format('%%%02X', string.byte(c))
  end

  local function guessMatch(pattern)
    local p = pattern
    p = string.gsub(p, '%%[aglwxUCDPS]', 'a')
    p = string.gsub(p, '%%[dAL]', '0')
    p = string.gsub(p, '%%[sGWX]', ' ')
    p = string.gsub(p, '%%u', 'A')
    p = string.gsub(p, '%%c', '\t')
    p = string.gsub(p, '%%p', ',')
    p = string.gsub(p, '%%(%W)', encodePercentChar) -- protect escaped characters
    p = string.gsub(p, '%[(.).*%]', '%1') -- replace set by the first one
    p = string.gsub(p, '%((.+)%)', '%1') -- remove captures
    p = string.gsub(p, '(.)[%+%?]', '%1') -- keep one or more and zero or one patterns
    p = string.gsub(p, '.[%*%-]', '') -- remove zero or more patterns
    return Url.decodePercent(p)
  end

  --- Returns a path that match this context.
  -- @treturn string the base path
  function httpContext:getBasePath()
    if not self.basePath then
      self.basePath = guessMatch(self:getPath())
    end
    return self.basePath
  end

  --- Sets the base path, default is guessed from the context path.
  -- @param basePath the base path
  -- @return this context
  function httpContext:setBasePath(basePath)
    self.basePath = basePath
    return self
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
  -- @treturn string the first captured value or the whole path, nil if the path does not match
  function httpContext:getArguments(path)
    return string.match(path, self.pattern)
  end

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
  HttpContext.computeIndex = computeIndex

end)

--- The HttpContext class.
HttpServer.HttpContext = HttpContext

return HttpServer
