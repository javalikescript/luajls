--- Provide a simple REST HTTP handler based on a Lua table.
-- @module jls.net.http.handler.RestHttpHandler
-- @pragma nostrip

local json = require('jls.util.json')
local Promise = require('jls.lang.Promise')
local HttpMessage = require('jls.net.http.HttpMessage')
local HttpExchange = require('jls.net.http.HttpExchange')

--- A RestHttpHandler class.
-- @type RestHttpHandler
return require('jls.lang.class').create('jls.net.http.HttpHandler', function(restHttpHandler, _, RestHttpHandler)

  --- Creates a REST @{HttpHandler}.
  -- @tparam table handlers the REST path handlers as a Lua table.
  function restHttpHandler:initialize(handlers, attributes)
    self.handlers = handlers or {}
    if type(attributes) == 'table' then
      self.attributes = attributes
    end
  end

  function restHttpHandler:handle(httpExchange)
    if self.attributes then
      httpExchange:setAttributes(self.attributes)
    end
    local path = httpExchange:getRequestArguments()
    local result = RestHttpHandler.restPart(self.handlers, httpExchange, path)
    if result == nil then
      HttpExchange.ok(httpExchange)
    elseif result == RestHttpHandler.REST_NOT_FOUND then
      HttpExchange.notFound(httpExchange)
    elseif type(result) == 'string' then
      HttpExchange.ok(httpExchange, result, HttpExchange.CONTENT_TYPES.txt)
    elseif type(result) == 'table' then
      HttpExchange.ok(httpExchange, json.encode(result), HttpExchange.CONTENT_TYPES.json)
    elseif result == false then
      -- response by handler
    elseif Promise:isInstance(result) then
      return result
    else
      HttpExchange.internalServerError(httpExchange)
    end
  end

  function RestHttpHandler.shiftPath(path)
    return string.match(path, '^([^/]+)/?(.*)$')
  end

  RestHttpHandler.REST_NOT_FOUND = {}
  RestHttpHandler.REST_ANY = '/any'

  function RestHttpHandler.replyJson(httpExchange, t)
    local response = httpExchange:getResponse()
    response:setStatusCode(HttpMessage.CONST.HTTP_OK, 'OK')
    response:setContentType(HttpExchange.CONTENT_TYPES.json)
    response:setBody(json.encode(t))
  end

  function RestHttpHandler.restPart(handlers, httpExchange, path)
    local name, remainingPath = RestHttpHandler.shiftPath(path)
    local handler
    if name then
      handler = handlers[RestHttpHandler.REST_ANY]
      if handler then
        if type(handlers.name) == 'string' then
          local value = name
          if type(handlers.value) == 'function' then
            value = handlers.value(httpExchange, name)
          end
          if value == nil then
            return RestHttpHandler.REST_NOT_FOUND
          end
          httpExchange:setAttribute(handlers.name, value)
        end
      elseif handlers[name] then
        handler = handlers[name]
      end
    else
      handler = handlers['']
    end
    if type(handler) == 'table' then
      return RestHttpHandler.restPart(handler, httpExchange, remainingPath)
    elseif type(handler) == 'function' then
      httpExchange:setAttribute('path', remainingPath)
      return handler(httpExchange)
    end
    if path == 'names' then
      local names = {}
      for n in pairs(handlers) do
        table.insert(names, n)
      end
      return names
    end
    return RestHttpHandler.REST_NOT_FOUND
  end

end)
