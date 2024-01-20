--[[--
Provides HTTP handler class and utility functions.

An HTTP handler provides a way to deal with an HTTP request.
Basicaly it consists in a function that will be called when an HTTP request
has been received but before the request body was consumed.

@module jls.net.http.HttpHandler
@pragma nostrip

@usage
local handler = HttpHandler:new(function(self, exchange)
  local response = exchange:getResponse()
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
  -- @tparam HttpExchange exchange the HTTP exchange to handle
  -- @treturn jls.lang.Promise a optional promise that resolves once the response is completed.
  function httpHandler:handle(exchange)
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
    return HttpHandler:new(function(self, exchange)
      local request = exchange:getRequest()
      request:bufferBody()
      return request:consume():next(function()
        local r = fn(exchange)
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

  --- Exposes a file system directory.
  -- @tparam File dir the base directory or a ZIP file.
  -- @tparam[opt] string permissions a string containing the granted permissions, 'rwxlcud' default is 'r'.
  -- @tparam[opt] string filename the name of the file to use in case of GET request on a directory, default is 'index.html'.
  -- @treturn HttpHandler a HttpHandler.
  function HttpHandler.file(dir, ...)
    local file = require('jls.io.File').asFile(dir)
    if file:isFile() and file:getExtension() == 'zip' then
      return require('jls.net.http.handler.ZipFileHttpHandler'):new(file)
    end
    return require('jls.net.http.handler.FileHttpHandler'):new(file, ...)
  end
  --- Exposes a file system directory.
  -- @tparam File dir the base directory or a ZIP file.
  -- @tparam[opt] string permissions a string containing the granted permissions, 'rwxlcud' default is 'r'.
  -- @tparam[opt] string filename the name of the file to use in case of GET request on a directory, default is 'index.html'.
  -- @treturn HttpHandler a HttpHandler.
  function HttpHandler.htmlFile(dir, ...)
    local file = require('jls.io.File').asFile(dir)
    return require('jls.net.http.handler.HtmlFileHttpHandler'):new(file, ...)
  end
  --- Proxies HTTP requests and responses.
  -- @treturn HttpHandler a HttpHandler.
  function HttpHandler.proxy()
    return require('jls.net.http.handler.ProxyHttpHandler'):new()
  end
  --[[-- Creates a router HTTP handler.
  This handler helps to expose REST APIs.
  
  The `handlers` consists in a deep table of functions representing the resource paths.
  By default the request body is processed and the JSON value is available with the attribute `requestJson`.

  The function returned value is used for the HTTP response.
  A table will be returned as a JSON value.
  The returned value could also be a @{jls.lang.Promise}.

  An empty string is used as table key for the root resource.
  The special table key `{name}` is used to match any key and provide the value in the attribue `name`.
  
  @tparam table handlers the path handlers as a Lua table.
  @treturn HttpHandler a HttpHandler.
  @usage
  local users = {}
  httpServer:createContext('/(.*)', HttpHandler.router({
    users = {
      [''] = function(exchange)
        return users
      end,
      -- additional handler
      ['{+}?method=GET'] = function(exchange, userId)
        exchange:setAttribute('user', users[userId])
      end,
      ['{userId}'] = {
        ['(user)?method=GET'] = function(exchange, user)
          return user
        end,
        ['(userId, requestJson)?method=POST,PUT'] = function(exchange, userId, requestJson)
          users[userId] = requestJson
        end,
        -- will be available at /rest/users/{userId}/greetings
        ['greetings(user)?method=GET'] = function(exchange, user)
          return 'Hello '..user.firstname
        end
      },
    }
  }))
  ]]
  function HttpHandler.router(...)
    return require('jls.net.http.handler.RouterHttpHandler'):new(...)
  end
  function HttpHandler.rest(...)
    return require('jls.net.http.handler.RouterHttpHandler'):new(...)
  end
  --- Exposes a table content throught HTTP APIs.
  -- This handler allows to access and maintain a deep Lua table.
  -- The GET response is a JSON with a 'value' key containing the table path value.
  -- @tparam table table the table.
  -- @tparam[opt] string path the table base path.
  -- @tparam[opt] boolean editable true to indicate that the table can be modified.
  -- @treturn HttpHandler a HttpHandler.
  function HttpHandler.table(...)
    return require('jls.net.http.handler.TableHttpHandler'):new(...)
  end

end)
