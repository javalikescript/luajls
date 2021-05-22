--- The HttpContext class maps a path to a handler.
-- @module jls.net.http.HttpContext
-- @pragma nostrip

local HttpMessage = require('jls.net.http.HttpMessage')
local HttpHandler = require('jls.net.http.HttpHandler')

--- The HttpContext class maps a path to a handler.
-- The HttpContext is used by the @{HttpServer} through the @{HttpContextHolder}.
-- @type HttpContext
return require('jls.lang.class').create('jls.net.http.Attributes', function(httpContext, super, HttpContext)

  --- Creates a new Context.
  -- The handler will be called when the request headers have been received if specified.
  -- The handler will be called when the body has been received if no response has been set.
  -- @tparam string path the context path
  -- @tparam function handler the context handler
  --   the function takes one argument which is an @{HttpExchange}.
  -- @tparam[opt] table attributes the optional context attributes
  -- @function HttpContext:new
  function httpContext:initialize(path, handler, attributes)
    super.initialize(self, attributes)
    if type(path) == 'string' then
      self.pattern = '^'..path..'$'
    else
      error('Invalid context path, type is '..type(path))
    end
    self.index = string.len(path)
    self:setHandler(handler or HttpContext.notFoundHandler)
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

  function httpContext:getPath()
    return string.sub(self.pattern, 2, -2)
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
    return select(3, string.find(path, self.pattern))
  end

  function httpContext:matchRequest(path, request)
    if string.match(path, self.pattern) then
      return true
    end
    return false
  end

  function httpContext:handleExchange(httpExchange)
    return self.handler:handle(httpExchange)
  end

  function httpContext:copyContext()
    return HttpContext:new(self:getPath(), self:getHandler(), self:getAttributes())
  end

  function httpContext:close()
    if type(self.handler.close) == 'function' then
      self.handler:close()
    end
  end

  HttpContext.notFoundHandler = HttpHandler:new(function(self, httpExchange)
    local response = httpExchange:getResponse()
    response:setStatusCode(HttpMessage.CONST.HTTP_NOT_FOUND, 'Not Found')
    response:setBody('<p>The resource "'..httpExchange:getRequest():getTarget()..'" is not available.</p>')
  end)

end)

