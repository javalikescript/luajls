--- A class that holds HTTP contexts.
-- @module jls.net.http.HttpContextHolder
-- @pragma nostrip

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
