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
    self.parent = nil
    self.notFoundContext = HttpContext:new('not found', HttpContext.notFoundHandler)
  end

  --- Creates a @{jls.net.http.HttpContext|context} in this server with the specified path and using the specified handler.
  -- @tparam string path The path of the context.
  --   The path is absolute and must start with a slash '/'.
  --   The path is a Lua pattern that match the full path.
  -- @tparam function handler The handler function.
  --   The function takes one argument which is an @{HttpExchange}.
  -- @tparam[opt] table attributes the optional context attributes
  -- @return the new context
  function httpContextHolder:createContext(path, handler, ...)
    if type(path) ~= 'string' or not string.match(path, '^/') then
      error('Invalid context path "'..tostring(path)..'"')
    end
    local context = HttpContext:new(path, handler, ...)
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

  function httpContextHolder:getParent()
    return self.parent
  end

  function httpContextHolder:setParent(parent)
    self.parent = parent
    return self
  end

  function httpContextHolder:getMatchingContext(path)
    local context, contextPath, maxLen = self.notFoundContext, '', 0
    for p, c in pairs(self.contexts) do
      local pLen = string.len(p)
      if pLen > maxLen and string.match(path, '^'..p..'$') then
        maxLen = pLen
        context = c
        contextPath = p
      end
    end
    if self.parent then
      context = self.parent:getMatchingContext(path)
    end
    if logger:isLoggable(logger.FINE) then
      logger:fine('httpContextHolder:getMatchingContext("'..path..'") => "'..contextPath..'"')
    end
    return context
  end

  -- TODO Remove
  function httpContextHolder:toHandler()
    return function(httpExchange)
      local request = httpExchange:getRequest()
      local context = self:getMatchingContext(request:getTargetPath())
      return httpExchange:handleRequest(context)
    end
  end

end)
