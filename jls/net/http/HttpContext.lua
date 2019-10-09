--- The HttpContext class maps a path to a handler.
-- @module jls.net.http.HttpContext
-- @pragma nostrip

local HttpMessage = require('jls.net.http.HttpMessage')

--- The HttpContext class maps a path to a handler.
-- The HttpContext is used by the @{HttpServer} through the @{HttpContextHolder}.
-- @type HttpContext
return require('jls.lang.class').create(require('jls.net.http.Attributes'), function(httpContext, super, HttpContext)

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

  function HttpContext.notFoundHandler(httpExchange)
    local response = httpExchange:getResponse()
    response:setStatusCode(HttpMessage.CONST.HTTP_NOT_FOUND, 'Not Found')
    response:setBody('<p>The resource "'..httpExchange:getRequest():getTarget()..'" is not available.</p>')
  end

end)

