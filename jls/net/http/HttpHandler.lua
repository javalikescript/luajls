--[[--
Provides HTTP handler class and utility functions.

An HTTP handler provides a way to deal with an HTTP request.
Basicaly it consists in a function that will be called when an HTTP request
has been received but before the request body was consumed.

@module jls.net.http.HttpHandler
@pragma nostrip

@usage
local handler = HttpHandler:new(function(self, httpExchange)
  local response = httpExchange:getResponse()
  response:setBody('It works !')
end)
]]

local Promise = require('jls.lang.Promise')
local Exception = require('jls.lang.Exception')

--- A HttpHandler class.
-- The handler is called when the request headers are available.
-- @type HttpHandler
return require('jls.lang.class').create(function(httpHandler)

  --- Creates an HTTP handler.
  -- @tparam[opt] function fn a function that will handle the HTTP exchange
  -- @function HttpHandler:new
  function httpHandler:initialize(fn)
    if type(fn) == 'function' then
      self.handle = fn
    end
  end

  --- Handles the request for the specified exchange.
  -- @tparam HttpExchange httpExchange the HTTP exchange to handle
  -- @treturn jls.lang.Promise a optional promise that resolves once the response is completed.
  function httpHandler:handle(httpExchange)
  end

  --- Closes this request handler.
  -- Do nothing by default. Must support to be called multiple times.
  function httpHandler:close()
  end

end, function(HttpHandler)

  function HttpHandler.onBodyHandler(fn)
    if type(fn) ~= 'function' then
      error('Invalid on body function handler, type is '..type(fn))
    end
    return HttpHandler:new(function(self, httpExchange)
      return httpExchange:onRequestBody(true):next(function()
        local r = fn(httpExchange)
        if Promise:isInstance(r) then
          return r
        end
      end)
    end)
  end

  local function chainHandlers(handlers, condition, exchange, index, cb)
    local handler = handlers[index]
    if not handler then
      exchange:getClass().notFound(exchange) -- Not found
      cb()
      return
    end
    local checkCondition = function()
      if condition(exchange) then
        chainHandlers(handlers, condition, exchange, index + 1, cb)
      else
        cb()
      end
    end
    local status, result = Exception.pcall(handler.handle, handler, exchange)
    if status then
      if Promise:isInstance(result) then
        result:next(checkCondition, function(reason)
          cb(reason or 'Error')
        end)
      else
        checkCondition()
      end
    else
      cb(result or 'Error')
    end
  end

  local function chainCondition(exchange)
    return exchange:getResponse():getStatusCode() == 403
  end

  -- Returns an handler that chain the specified handlers
  function HttpHandler.chain(...)
    local handlers = {...}
    local condition = chainCondition
    if type(handlers[1]) == 'function' then
      condition = table.remove(handlers, 1)
    end
    return HttpHandler:new(function(_, exchange)
      local p, cb = Promise.createWithCallback()
      chainHandlers(handlers, condition, exchange, 1, cb)
      return p
    end)
  end

  --- Creates a FileHttpHandler.
  -- @tparam File rootFile the root File
  -- @tparam[opt] string permissions a string containing the granted permissions, 'rwxlcud' default is 'r'
  -- @tparam[opt] string filename the name of the file to use in case of GET request on a directory, default is 'index.html'
  -- @treturn HttpHandler a HttpHandler.
  function HttpHandler.file(...)
    return require('jls.net.http.handler.FileHttpHandler'):new(...)
  end
  --- Creates a ProxyHttpHandler.
  -- @treturn HttpHandler a HttpHandler.
  function HttpHandler.proxy(...)
    return require('jls.net.http.handler.ProxyHttpHandler'):new(...)
  end
  --- Creates a RestHttpHandler.
  -- @tparam table handlers the REST path handlers as a Lua table.
  -- @treturn HttpHandler a HttpHandler.
  function HttpHandler.rest(...)
    return require('jls.net.http.handler.RestHttpHandler'):new(...)
  end
  --- Creates a TableHttpHandler.
  -- @tparam table table the table.
  -- @tparam[opt] string path the table base path.
  -- @tparam[opt] boolean editable true to indicate that the table can be modified.
  -- @treturn HttpHandler a HttpHandler.
  function HttpHandler.table(...)
    return require('jls.net.http.handler.TableHttpHandler'):new(...)
  end
  --- Creates a WebDavHttpHandler.
  -- See FileHttpHandler
  -- @treturn HttpHandler a HttpHandler.
  function HttpHandler.webDav(...)
    return require('jls.net.http.handler.WebDavHttpHandler'):new(...)
  end
  --- Creates a ZipFileHttpHandler.
  -- @tparam jls.io.File zipFile the ZIP file.
  -- @treturn HttpHandler a HttpHandler.
  function HttpHandler.zipFile(...)
    return require('jls.net.http.handler.ZipFileHttpHandler'):new(...)
  end

end)
