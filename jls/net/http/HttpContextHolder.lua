--- A class that holds @{jls.net.http.HttpContext|HTTP contexts}.
-- @module jls.net.http.HttpContextHolder
-- @pragma nostrip

local logger = require('jls.lang.logger')
local HttpContext = require('jls.net.http.HttpContext')

--- A class that holds HTTP contexts.
-- @type HttpContextHolder
return require('jls.lang.class').create(function(httpContextHolder)

  --- Creates a new ContextHolder.
  -- @function HttpContextHolder:new
  function httpContextHolder:initialize()
    self.contexts = {}
    self.notFoundContext = HttpContext:new(HttpContext.notFoundHandler)
  end

  --- Creates a @{jls.net.http.HttpContext|context} in this server with the specified path and using the specified handler.
  -- @tparam string path The path of the context.
  -- @tparam function handler The handler function
  --   the function takes one argument which is an @{HttpExchange}.
  -- @tparam[opt] table attributes the optional context attributes
  -- @tparam[opt] boolean headersHandler true to indicate that the handler is also used for headers
  -- @return the new context
  function httpContextHolder:createContext(path, handler, ...)
    if type(path) ~= 'string' or path == '' then
      error('Invalid context path')
    end
    if type(handler) ~= 'function' then
      error('Invalid context handler type '..type(handler))
    end
    local context = HttpContext:new(handler, path, ...)
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
    local context, contextPath, maxLen = self.notFoundContext, '', 0
    for p, c in pairs(self.contexts) do
      local pLen = string.len(p)
      if pLen > maxLen and string.find(path, '^'..p..'$') then
        maxLen = pLen
        context = c
        contextPath = p
      end
    end
    if logger:isLoggable(logger.FINE) then
      logger:fine('httpContextHolder:getHttpContext("'..path..'") => "'..contextPath..'"')
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
