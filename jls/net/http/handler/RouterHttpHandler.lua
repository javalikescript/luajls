--- Provide a simple router HTTP handler.
-- @module jls.net.http.handler.RouterHttpHandler
-- @pragma nostrip

local class = require('jls.lang.class')
local logger = require('jls.lang.logger'):get(...)
local Promise = require('jls.lang.Promise')
local Exception = require('jls.lang.Exception')
local json = require('jls.util.json')
local strings = require('jls.util.strings')
local HttpHandler = require('jls.net.http.HttpHandler')
local HttpMessage = require('jls.net.http.HttpMessage')
local HttpExchange = require('jls.net.http.HttpExchange')
local xml = require("jls.util.xml")

local ROUTER_DONE = {}
local ROUTER_NOT_FOUND = {}
local ROUTER_ANY = '{*}'
local ROUTER_ALL = '{+}'

--[[
see https://expressjs.com/en/starter/basic-routing.html
"Routing refers to determining how an application responds to a client request to a particular endpoint,
which is a URI (or path) and a specific HTTP request method (GET, POST, and so on)."
]]

-- the characters : / ? # [ ] @ are reserved for use as delimiters of the generic URI components

local function check(values, value)
  return not values or string.find(values, value, 1, true)
end

local function addAt(map, key, value)
  local values = map[key]
  if values then
    table.insert(values, value)
  else
    values = {value}
    map[key] = values
  end
  return values
end

local BaseHttpHandler = class.create(HttpHandler, function(baseHttpHandler)

  function baseHttpHandler:initialize(fn)
    self.fn = fn or class.emptyFunction
  end

  function baseHttpHandler:handle(exchange, capture)
    return self.fn(exchange, capture)
  end

end)

local RouteHttpHandler = class.create(HttpHandler, function(routeHttpHandler)

  function routeHttpHandler:initialize(infos, all)
    self.infos = infos or {}
    self.all = all
  end

  function routeHttpHandler:handle(exchange, capture)
    local request = exchange:getRequest()
    local accept = request:getHeader(HttpMessage.CONST.HEADER_ACCEPT)
    local contentType = request:getContentType()
    local method = request:getMethod()
    for _, info in ipairs(self.infos) do
      if check(info.method, method) and check(info.accept, accept) and check(info['content-type'], contentType) then
        local values, count = {}, 0
        if info.args then
          for index, name in ipairs(info.args) do
            local value = exchange:getAttribute(name)
            values[index] = value
          end
          count = #info.args
        end
        if self.all then
          local result = info.fn(exchange, capture, table.unpack(values, 1, count))
          if result ~= nil then
            return result
          end
        else
          return info.fn(exchange, table.unpack(values, 1, count))
        end
      end
    end
    if not self.all then
      return ROUTER_NOT_FOUND
    end
  end

end)

local function prepareHandlers(handlers)
  local preparedHandlers = {}
  local infosByPath = {}
  for fullPath, value in pairs(handlers) do
    local path, info
    path = fullPath
    if type(value) == 'function' then -- TODO accept HttpHandler instance
      info = {
        fn = value
      }
      local p, q = string.match(path, '^([^%?]*)%?(.+)$')
      if p then
        path = p
        for filterKey, filterValue in string.gmatch(q, "%s*([^&=%s]+)%s*=%s*([^&]+)%s*&?") do
          info[string.lower(filterKey)] = filterValue
        end
        info.args = {} -- to force processing query filters
      end
      p, q = string.match(path, '^(.*)%(([%a_][%a%d_,%s]*)%)$')
      if p then
        path = p
        -- TODO indicate that a parameter is mandatory or optional
        info.args = strings.split(q, '%s*,%s*')
      end
    end
    local name = string.match(path, '^{([%a_][%a%d_]*)}$')
    if name then
      path = ROUTER_ANY
      addAt(infosByPath, ROUTER_ALL, {
        fn = function(exchange, capture)
          exchange:setAttribute(name, capture)
        end
      })
    end
    if info then
      addAt(infosByPath, path, info)
    elseif type(value) == 'table' then
      preparedHandlers[path] = prepareHandlers(value)
    else
      preparedHandlers[path] = value
    end
  end
  for path, infos in pairs(infosByPath) do
    if #infos == 1 and not infos[1].args then
      preparedHandlers[path] = BaseHttpHandler:new(infos[1].fn)
    else
      logger:finer('Router path "%s" prepared with %s handlers', path, #infos)
      -- TODO Sort infos by info.order if available
      preparedHandlers[path] = RouteHttpHandler:new(infos, path == ROUTER_ALL)
    end
  end
  return preparedHandlers
end

local function shiftPath(path)
  return string.match(path, '^([^/]+)/?(.*)$')
end

local function routerPart(handlers, exchange, path)
  local name, remainingPath = shiftPath(path)
  local handler
  if name then
    handler = handlers[name]
    if not handler then
      handler = handlers[ROUTER_ANY]
    end
    local allHandler = handlers[ROUTER_ALL]
    if allHandler and HttpHandler:isInstance(allHandler) then
      local r = allHandler:handle(exchange, name)
      if r ~= nil then
        return r
      end
    end
  else
    handler = handlers['']
  end
  if type(handler) ~= 'table' then
    return ROUTER_NOT_FOUND
  end
  if HttpHandler:isInstance(handler) then
    exchange:setAttribute('path', remainingPath)
    return handler:handle(exchange)
  end
  return routerPart(handler, exchange, remainingPath)
end

local function processRestResponse(exchange, result)
  if result == nil then
    HttpExchange.ok(exchange)
  elseif result == ROUTER_DONE or result == false then
    -- response by handler
  elseif result == ROUTER_NOT_FOUND then
    HttpExchange.notFound(exchange)
  else
    local contentType = exchange:getResponse():getContentType()
    if contentType == HttpExchange.CONTENT_TYPES.json then
      HttpExchange.ok(exchange, json.stringify(result))
    elseif type(result) == 'string' then
      HttpExchange.ok(exchange, result, HttpExchange.CONTENT_TYPES.txt)
    elseif type(result) == 'table' then
      if contentType == HttpExchange.CONTENT_TYPES.xml then
        HttpExchange.ok(exchange, xml.encode(result))
      else
        HttpExchange.ok(exchange, json.stringify(result), HttpExchange.CONTENT_TYPES.json)
      end
    else
      HttpExchange.internalServerError(exchange)
    end
  end
end

--- A RouterHttpHandler class.
-- @type RouterHttpHandler
return class.create(HttpHandler, function(routerHttpHandler, _, RouterHttpHandler)

  --[[--
Creates a Router @{HttpHandler}.
This handler helps to expose REST APIs.
The handlers consists in a deep table of functions representing the resource paths.
The remainging path is available with the attribute "path".
By default the request body is processed and JSON value is available with the attribute "requestJson", XML value is available with the attribute "requestXml".
The function returned value is used for the HTTP response. A table will be returned as a JSON value. The returned value could also be a promise.
An empty string is used as table key for the root resource.
The special table key "{name}" is used to match any key and provide the value in the attribue "name".
@tparam table handlers the Router path handlers as a Lua table.
@tparam[opt] table attributes exchange attributes.
@tparam[opt] boolean noBody true to indicate the body should not be consumed.
@usage
local users = {}
httpServer:createContext('/(.*)', RouterHttpHandler:new({
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
  --]]
  function routerHttpHandler:initialize(handlers, attributes, noBody)
    self.handlers = prepareHandlers(handlers or {})
    if logger:isLoggable(logger.FINEST) then
      logger:finest('Router handlers')
      logger:finest(self.handlers)
    end
    if type(attributes) == 'table' then
      self.attributes = attributes
    end
    self.consumeBody = noBody ~= true
  end

  function routerHttpHandler:handleNow(exchange)
    local path = exchange:getRequestPath()
    local status, result = Exception.pcall(routerPart, self.handlers, exchange, path)
    if status then
      if Promise.isPromise(result) then
        return Promise.resolve(result):next(function(r)
          processRestResponse(exchange, r)
          return true
        end)
      end
      processRestResponse(exchange, result)
    else
      logger:warn('Router handler error: %s', result)
      HttpExchange.internalServerError(exchange)
    end
  end

  function routerHttpHandler:handle(exchange)
    if self.attributes then
      exchange:setAttributes(self.attributes)
    end
    if self.consumeBody then
      local request = exchange:getRequest()
      local length = request:getContentLength()
      if length and length > 0 then
        request:bufferBody()
        return request:consume():next(function()
          local contentType = request:getContentType()
          local method = request:getMethod()
          if method == HttpMessage.CONST.METHOD_POST or method == HttpMessage.CONST.METHOD_PUT then
            if contentType == HttpExchange.CONTENT_TYPES.json then
              local requestJson = json.decode(request:getBody()) -- TODO Handle parsing errors
              exchange:setAttribute('requestJson', requestJson)
            elseif contentType == HttpExchange.CONTENT_TYPES.xml then
              local requestXml = xml.decode(request:getBody()) -- TODO Handle parsing errors
              exchange:setAttribute('requestXml', requestXml)
            end
          end

          return self:handleNow(exchange)
        end)
      end
    end
    return self:handleNow(exchange)
  end

  function RouterHttpHandler.replyJson(exchange, t)
    local response = exchange:getResponse()
    response:setStatusCode(HttpMessage.CONST.HTTP_OK, 'OK')
    response:setContentType(HttpExchange.CONTENT_TYPES.json)
    response:setBody(json.stringify(t))
  end

  RouterHttpHandler.routerPart = routerPart
  RouterHttpHandler.shiftPath = shiftPath

  RouterHttpHandler.ROUTER_NOT_FOUND = ROUTER_NOT_FOUND
  RouterHttpHandler.ROUTER_DONE = ROUTER_DONE
  RouterHttpHandler.ROUTER_ANY = ROUTER_ANY
  RouterHttpHandler.ROUTER_ALL = ROUTER_ALL

  -- Deprecated, to remove
  RouterHttpHandler.restPart = routerPart
  RouterHttpHandler.REST_NOT_FOUND = ROUTER_NOT_FOUND
  RouterHttpHandler.REST_DONE = ROUTER_DONE
  RouterHttpHandler.REST_ANY = ROUTER_ANY
  RouterHttpHandler.REST_ALL = ROUTER_ALL

end)
