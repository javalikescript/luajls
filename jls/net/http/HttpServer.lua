--- An HTTP server implementation that handles HTTP requests.
-- @module jls.net.http.HttpServer
-- @pragma nostrip

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local net = require('jls.net')
local HttpMessage = require('jls.net.http.HttpMessage')
local HttpRequest = require('jls.net.http.HttpRequest')
local HttpResponse = require('jls.net.http.HttpResponse')
local HeaderStreamHandler = require('jls.net.http.HeaderStreamHandler')
local readBody = require('jls.net.http.readBody')


--- A class that holds attributes.
-- @type Attributes
local Attributes = class.create(function(attributes)

  --- Creates a new Attributes.
  -- @function Attributes:new
  function attributes:initialize(attributes)
    self.attributes = {}
    if attributes and type(attributes) == 'table' then
      self:setAttributes(attributes)
    end
  end

  --- Sets the specified value for the specified name.
  -- @tparam string name the attribute name
  -- @param value the attribute value
  function attributes:setAttribute(name, value)
    self.attributes[name] = value
    return self
  end

  --- Returns the value for the specified name.
  -- @tparam string name the attribute name
  -- @return the attribute value
  function attributes:getAttribute(name)
    return self.attributes[name]
  end

  function attributes:getAttributes()
    return self.attributes
  end

  function attributes:setAttributes(attributes)
    for name, value in pairs(attributes) do
      self:setAttribute(name, value)
    end
    return self
  end
end)


--- The HttpContext class maps a path to a handler.
-- The HttpContext is used by the @{HttpServer} through the @{HttpContextHolder}.
-- @type HttpContext
local HttpContext = class.create(Attributes, function(httpContext, super, HttpContext)

  --- Creates a new Context.
  -- @tparam function handler the context handler
  --   the function takes one argument which is an @{HttpExchange}.
  -- @tparam string path the context path
  -- @tparam[opt] table attributes the optional context attributes
  -- @function HttpContext:new
  function httpContext:initialize(handler, path, attributes)
    super.initialize(self, attributes)
    self.handler = handler
    self.path = path or ''
  end

  function httpContext:getHandler()
    return self.handler
  end

  function httpContext:setHandler(handler)
    self.handler = handler
    return self
  end

  function httpContext:getPath()
    return self.path
  end

  function httpContext:chainContext(context)
    return HttpContext:new(function(httpExchange)
      httpExchange:handleRequest(self):next(function()
        return httpExchange:handleRequest(context)
      end)
    return result
    end)
  end

  function httpContext:copyContext()
    return HttpContext:new(self:getHandler(), self:getPath(), self:getAttributes())
  end
end)


--- The HttpExchange class wraps the HTTP request and response.
-- @type HttpExchange
local HttpExchange = class.create(Attributes, function(httpExchange)

  --- Creates a new Exchange.
  -- @function HttpExchange:new
  function httpExchange:initialize(server, client)
    self.attributes = {}
    self.server = server
    self.client = client
  end

  --- Returns the HTTP context.
  -- @treturn HttpContext the HTTP context.
  function httpExchange:getContext()
    return self.context
  end

  function httpExchange:setContext(value)
    self.context = value
  end

  --- Returns the HTTP request.
  -- @treturn HttpRequest the HTTP request.
  function httpExchange:getRequest()
    return self.request
  end

  function httpExchange:setRequest(value)
    self.request = value
  end

  --- Returns the HTTP response.
  -- @treturn HttpResponse the HTTP response.
  function httpExchange:getResponse()
    return self.response
  end

  function httpExchange:setResponse(value)
    self.response = value
  end

  --- Returns the captured values of the request target path using the context path.
  -- @treturn string the first captured value, nil if there is no captured value.
  function httpExchange:getRequestArguments()
    return select(3, string.find(self:getRequest():getTargetPath(), '^'..self:getContext():getPath()..'$'))
  end

  --- Returns a new HTTP response.
  -- @treturn HttpResponse a new HTTP response.
  function httpExchange:createResponse()
    local response = HttpResponse:new()
    response:setHeader(HttpMessage.CONST.HEADER_CONNECTION, HttpMessage.CONST.CONNECTION_CLOSE)
    response:setHeader(HttpMessage.CONST.HEADER_SERVER, HttpMessage.CONST.DEFAULT_SERVER)
    return response
  end

  function httpExchange:prepareResponse(response)
    local body = response:getBody()
    if not response:getContentLength() then
      if type(body) == 'string' then
        response:setContentLength(string.len(body))
      else
        response:setContentLength(0)
      end
    end
  end

  function httpExchange:handleRequest(context)
    if logger:isLoggable(logger.FINER) then
      logger:finer('HttpServer:handleRequest() "'..self:getRequest():getTarget()..'"')
    end
    self:setContext(context)
    local status, result = pcall(function ()
      local handler = context:getHandler()
      return handler(self)
    end)
    if status then
      -- always return a promise
      if Promise:isInstance(result) then
        return result
      end
      return Promise.resolve()
    end
    if logger:isLoggable(logger.WARN) then
      logger:warn('HttpServer error while handling "'..self:getRequest():getTarget()..'", due to "'..tostring(result)..'"')
    end
    local response = self:getResponse()
    response:close()
    response = self:createResponse()
    response:setStatusCode(HttpMessage.CONST.HTTP_INTERNAL_SERVER_ERROR, 'Internal Server Error')
    self:setResponse(response)
    return Promise.reject(result or 'Unkown error')
  end

  function httpExchange:processResponse()
    if logger:isLoggable(logger.FINER) then
      logger:finer('httpExchange:processResponse()')
    end
    local response = self:getResponse()
    if not response then
      return Promise.reject('No response to process')
    end
    self:prepareResponse(response)
    return response:writeHeaders(self.client):next(function()
      return response:writeBody(self.client)
    end)
  end

  function httpExchange:processRequest()
    if logger:isLoggable(logger.FINER) then
      logger:finer('httpExchange:processRequest()')
    end
    local request = self:getRequest()
    local path = request:getTargetPath()
    local context = self.server:getHttpContext(path)
    self:setResponse(self:createResponse())
    return self:handleRequest(context)
  end

  function httpExchange:removeClient()
    local client = self.client
    self.client = nil
    return client
  end

  function httpExchange:close()
    logger:finest('httpExchange:close()')
    if self.request then
      self.request:close()
      self.request = nil
    end
    if self.response then
      self.response:close()
      self.response = nil
    end
    if self.client then
      --self.client:readStop()
      self.client:close()
      self.client = nil
    end
  end
end)

local function notFoundHandler(httpExchange)
  local response = httpExchange:getResponse()
  response:setStatusCode(HttpMessage.CONST.HTTP_NOT_FOUND, 'Not Found')
  response:setBody('<p>The resource "'..httpExchange:getRequest():getTarget()..'" is not available.</p>')
end


--- A class that holds HTTP contexts.
-- @type HttpContextHolder
local HttpContextHolder = class.create(function(httpContextHolder)

  --- Creates a new ContextHolder.
  -- @function HttpContextHolder:new
  function httpContextHolder:initialize()
    self.contexts = {}
    self.notFoundContext = HttpContext:new(notFoundHandler)
  end

  --- Creates a context in this server with the specified path and using the specified handler.
  -- @tparam string path The path of the context.
  -- @tparam function handler The handler function
  --   the function takes one argument which is an @{HttpExchange}.
  -- @param[opt] attributes The context attributes.
  -- @return the new context
  function httpContextHolder:createContext(path, handler, attributes)
    if type(path) ~= 'string' or path == '' then
      error('Invalid context path')
    end
    if type(handler) ~= 'function' then
      error('Invalid context handler type '..type(handler))
    end
    local context = HttpContext:new(handler, path, attributes)
    self.contexts[context:getPath()] = context
    return context
  end

  function httpContextHolder:removeContext(pathOrContext)
    if type(pathOrContext) == 'string' then
      self.contexts[pathOrContext] = nil
    elseif HttpContext:isInstance(pathOrContext) then
      for p, c in pairs(self.contexts) do
        if c == pathOrContext then
          self.contexts[p] = nil
        end
      end
    end
  end

  function httpContextHolder:removeAllContexts()
    self.contexts = {}
  end

  --[[
  function httpContextHolder:getHttpContexts()
    return self.contexts
  end

  function httpContextHolder:setHttpContexts(contexts)
    self.contexts = contexts
    return self
  end

  function httpContextHolder:addHttpContexts(contexts)
    for p, c in pairs(contexts) do
      self.contexts[p] = c
    end
    return self
  end
  ]]

  function httpContextHolder:getHttpContext(path)
    local context, maxLen = self.notFoundContext, 0
    for p, c in pairs(self.contexts) do
      local pLen = string.len(p)
      if pLen > maxLen and string.find(path, '^'..p..'$') then
        maxLen = pLen
        context = c
      end
    end
    return context
  end

  function httpContextHolder:toHandler()
    return function(httpExchange)
      local request = httpExchange:getRequest()
      local context = self:getHttpContext(request:getTargetPath())
      return httpExchange:handleRequest(context)
    end
  end
end)


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
return class.create(HttpContextHolder, function(httpServer, super)

  --- Creates a new HTTP server.
  -- @function HttpServer:new
  -- @return a new HTTP server
  function httpServer:initialize(tcp)
    super.initialize(self)
    self.tcpServer = tcp or net.TcpServer:new()
    local server = self
    function self.tcpServer:onAccept(client)
      server:onAccept(client)
    end
  end

  --[[
    The presence of a message body in a request is signaled by a
  Content-Length or Transfer-Encoding header field.  Request message
  framing is independent of method semantics, even if the method does
  not define any use for a message body
  ]]
  function httpServer:onAccept(client, buffer)
    logger:finer('httpServer:onAccept()')
    local server = self
    local exchange = HttpExchange:new(server, client)
    local request = HttpRequest:new()
    local keepAlive = false
    local remainingBuffer = nil
    local hsh = HeaderStreamHandler:new(request)
    -- TODO limit headers
    hsh:read(client, buffer):next(function(remainingHeaderBuffer)
      logger:finer('httpServer:onAccept() header read')
      exchange:setRequest(request)
      if request then
        keepAlive = request:getHeader(HttpMessage.CONST.HEADER_CONNECTION) == HttpMessage.CONST.CONNECTION_KEEP_ALIVE
      end
      -- TODO limit request body
      return readBody(request, client, remainingHeaderBuffer)
    end):next(function(remainingBodyBuffer)
      logger:fine('httpServer:onAccept() body done')
      remainingBuffer = remainingBodyBuffer
      return exchange:processRequest()
    end):next(function()
      logger:fine('httpServer:onAccept() request processed')
      if keepAlive and exchange:getResponse() then
        exchange:getResponse():setHeader(HttpMessage.CONST.HEADER_CONNECTION, HttpMessage.CONST.CONNECTION_KEEP_ALIVE)
      end
      local status, res = pcall(function ()
        return exchange:processResponse()
      end)
      if not status then
        logger:warn('HttpExchange:processResponse() in error due to "'..tostring(res)..'"')
        return Promise.reject(res)
      end
      return res
    end):next(function()
      logger:fine('httpServer:onAccept() response processed')
      --local response = exchange:getResponse()
      if keepAlive then
        local c = exchange:removeClient()
        if c then
          logger:fine('httpServer:onAccept() keeping client alive')
          exchange:close()
          return server:onAccept(c, remainingBuffer)
        end
      end
      exchange:close()
    end, function(err)
      if logger:isLoggable(logger.FINE) then
        logger:fine('httpServer:onAccept() read header error "'..tostring(err)..'"')
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

  HttpServer.notFoundHandler = notFoundHandler

end)
