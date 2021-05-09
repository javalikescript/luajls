--- A class that holds @{jls.net.http.HttpContext|HTTP contexts}.
-- @module jls.net.http.HttpContextHolder
-- @pragma nostrip

local logger = require('jls.lang.logger')
local TableList = require('jls.util.TableList')
local HttpContext = require('jls.net.http.HttpContext')
local HttpFilter = require('jls.net.http.HttpFilter')

local function compareByLength(a, b)
  local la = string.len(a:getPath())
  local lb = string.len(b:getPath())
  return la > lb
end

--- A class that holds HTTP contexts.
-- @type HttpContextHolder
return require('jls.lang.class').create(function(httpContextHolder)

  --- Creates a new ContextHolder.
  -- @function HttpContextHolder:new
  function httpContextHolder:initialize()
    self.contexts = {}
    self.filters = {}
    self.parentContextHolder = nil
    self.notFoundContext = HttpContext:new('not found', HttpContext.notFoundHandler)
  end

  --- Creates a @{jls.net.http.HttpContext|context} in this server with the specified path and using the specified handler.
  -- @tparam string path The path of the context.
  --   The path is absolute and must start with a slash '/'.
  --   The path is a Lua pattern that match the full path.
  -- @param handler The @{jls.net.http.HttpHandler|handler} or a handler function.
  --   The function takes one argument which is the @{HttpExchange} and will be called when the body is available.
  -- @tparam[opt] table attributes the optional context attributes
  -- @return the new context
  function httpContextHolder:createContext(path, handler, ...)
    if type(path) ~= 'string' or not string.match(path, '^/') then
      error('Invalid context path "'..tostring(path)..'"')
    end
    local context = HttpContext:new(path, handler, ...)
    table.insert(self.contexts, context)
    table.sort(self.contexts, compareByLength)
    return context
  end

  function httpContextHolder:removeContext(pathOrContext)
    if type(pathOrContext) == 'string' then
      local context = self:findContext(pathOrContext)
      if context then
        TableList.removeFirst(self.contexts, context)
      end
    elseif HttpContext:isInstance(pathOrContext) then
      TableList.removeAll(self.contexts, pathOrContext)
    end
  end

  function httpContextHolder:removeAllContexts()
    self.contexts = {}
  end

  function httpContextHolder:addFilter(filter)
    if type(filter) == 'function' then
      filter = HttpFilter:new(filter)
    elseif not HttpFilter:isInstance(filter) then
      error('Invalid filter argument, type is '..type(filter))
    end
    table.insert(self.filters, filter)
    return filter
  end

  function httpContextHolder:removeFilter(filter)
    TableList.removeAll(self.filters, filter)
  end

  function httpContextHolder:removeAllFilters()
    self.filters = {}
  end

  function httpContextHolder:getFilters()
    return self.filters
  end

  function httpContextHolder:getParentContextHolder()
    return self.parentContextHolder
  end

  function httpContextHolder:setParentContextHolder(parent)
    self.parentContextHolder = parent
    return self
  end

  function httpContextHolder:findContext(path)
    for _, context in ipairs(self.contexts) do
      if context:matchPath(path) then
        return context
      end
    end
    return nil
  end

  function httpContextHolder:getMatchingContext(path)
    local context = self:findContext(path)
    if not context then
      if self.parentContextHolder then
        context = self.parentContextHolder:findContext(path) or self.notFoundContext
      else
        context = self.notFoundContext
      end
    end
    if logger:isLoggable(logger.FINE) then
      logger:fine('httpContextHolder:getMatchingContext("'..path..'") => "'..context:getPath()..'"')
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
