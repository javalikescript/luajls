--- The HttpContext class maps a path to a handler.
-- @module jls.net.http.HttpContext
-- @pragma nostrip

local HttpMessage = require('jls.net.http.HttpMessage')

--- The HttpContext class maps a path to a handler.
-- The HttpContext is used by the @{HttpServer} through the @{HttpContextHolder}.
-- @type HttpContext
return require('jls.lang.class').create(require('jls.net.http.Attributes'), function(httpContext, super, HttpContext)

  --- Creates a new Context.
  -- The handler will be called when the request headers have been received if specified.
  -- The handler will be called when the body has been received if no response has been set.
  -- @tparam function handler the context handler
  --   the function takes one argument which is an @{HttpExchange}.
  -- @tparam string path the context path
  -- @tparam[opt] table attributes the optional context attributes
  -- @tparam[opt] boolean headersHandler true to indicate that the handler is also used for headers
  -- @function HttpContext:new
  function httpContext:initialize(handler, path, attributes, headersHandler)
    super.initialize(self, attributes)
    self.handler = handler
    self.path = path or ''
    self.headersHandler = headersHandler == true
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

  --- Returns the captured values of the specified path.
  -- @treturn string the first captured value, nil if there is no captured value.
  function httpContext:getArguments(path)
    return select(3, string.find(path, '^'..self.path..'$'))
  end

  function httpContext:isHeadersHandler()
    return self.headersHandler == true
  end

  function httpContext:handleExchange(httpExchange)
    return self.handler(httpExchange)
  end

  function httpContext:chainContext(context)
    return HttpContext:new(function(httpExchange)
      httpExchange:handleRequest(self):next(function()
        return httpExchange:handleRequest(context)
      end)
    end)
  end

  function httpContext:copyContext()
    return HttpContext:new(self:getHandler(), self:getPath(), self:getAttributes(), self:isHeadersHandler())
  end

  function HttpContext.notFoundHandler(httpExchange)
    local response = httpExchange:getResponse()
    response:setStatusCode(HttpMessage.CONST.HTTP_NOT_FOUND, 'Not Found')
    response:setBody('<p>The resource "'..httpExchange:getRequest():getTarget()..'" is not available.</p>')
  end

end)

