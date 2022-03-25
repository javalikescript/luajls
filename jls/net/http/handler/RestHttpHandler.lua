--- Provide a simple REST HTTP handler based on a Lua table.
-- @module jls.net.http.handler.RestHttpHandler
-- @pragma nostrip

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local protectedCall = require('jls.lang.protectedCall')
local json = require('jls.util.json')
local strings = require('jls.util.strings')
local HttpMessage = require('jls.net.http.HttpMessage')
local HttpExchange = require('jls.net.http.HttpExchange')
local xml = require("jls.util.xml")

local REST_DONE = {}
local REST_NOT_FOUND = {}
local REST_ANY = '{*}'
local REST_ALL = '{+}'

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

local function prepareHandlers(handlers)
  local preparedHandlers = {}
  local infosByPath = {}
  for fullPath, handler in pairs(handlers) do
    local path, info
    path = fullPath
    if type(handler) == 'function' then
      info = {
        handler = handler
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
        info.args = strings.split(q, '%s*,%s*')
      end
    end
    local capture = string.match(path, '^{([%a_][%a%d_]*)}$')
    if capture then
      path = REST_ANY
      addAt(infosByPath, REST_ALL, {
        handler = function(exchange, value)
          exchange:setAttribute(capture, value)
        end
      })
    end
    if info then
      addAt(infosByPath, path, info)
    elseif type(handler) == 'table' then
      preparedHandlers[path] = prepareHandlers(handler)
    else
      preparedHandlers[path] = handler
    end
  end
  for path, infos in pairs(infosByPath) do
    if #infos == 1 and not infos[1].args then
      preparedHandlers[path] = infos[1].handler
    else
      if logger:isLoggable(logger.FINER) then
        logger:finer('REST path "'..tostring(path)..'" prepared with '..tostring(#infos)..' handlers')
      end
      -- TODO Sort infos by info.order if available
      preparedHandlers[path] = function(exchange, ...)
        local request = exchange:getRequest()
        local accept = request:getHeader(HttpMessage.CONST.HEADER_ACCEPT)
        local contentType = request:getContentType()
        local method = request:getMethod()
        for _, info in ipairs(infos) do
          if check(info.method, method) and check(info.accept, accept) and check(info['content-type'], contentType) then
            local values = {...}
            if info.args then
              for _, name in ipairs(info.args) do
                table.insert(values, exchange:getAttribute(name) or false)
              end
            end
            local result = info.handler(exchange, table.unpack(values))
            if result ~= nil or path ~= REST_ALL then
              return result
            end
          end
        end
        if path ~= REST_ALL then
          return REST_NOT_FOUND
        end
      end
    end
  end
  return preparedHandlers
end

local function shiftPath(path)
  return string.match(path, '^([^/]+)/?(.*)$')
end

local function restPart(handlers, exchange, path)
  local name, remainingPath = shiftPath(path)
  local handler
  if name then
    handler = handlers[name]
    if not handler then
      handler = handlers[REST_ANY]
    end
    local allHandler = handlers[REST_ALL]
    if type(allHandler) == 'function' then
      local r = allHandler(exchange, name)
      if r ~= nil then
        return r
      end
    end
  else
    handler = handlers['']
  end
  if type(handler) == 'table' then
    return restPart(handler, exchange, remainingPath)
  elseif type(handler) == 'function' then
    exchange:setAttribute('path', remainingPath)
    return handler(exchange)
  end
  return REST_NOT_FOUND
end

local function processRestResponse(exchange, result)
  if result == nil then
    HttpExchange.ok(exchange)
  elseif result == REST_DONE or result == false then
    -- response by handler
  elseif result == REST_NOT_FOUND then
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

--- A RestHttpHandler class.
-- @type RestHttpHandler
return require('jls.lang.class').create('jls.net.http.HttpHandler', function(restHttpHandler, _, RestHttpHandler)

  --[[--
Creates a REST @{HttpHandler}.
The handlers consists in a deep table of functions representing the resource paths.
By default the request body is processed and JSON value is available with the attribute "requestJson".
The function returned value is used for the HTTP response. A table will be returned as a JSON value. The returned value could also be a promise.
An empty string is used as table key for the root resource.
The special table key "{name}" is used to match any key and provide the value in the attribue "name".
@tparam table handlers the REST path handlers as a Lua table.
@tparam[opt] table attributes exchange attributes.
@tparam[opt] boolean noBody true to indicate the body should not be consumed.
@usage
local users = {}
httpServer:createContext('/(.*)', RestHttpHandler:new({
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
  function restHttpHandler:initialize(handlers, attributes, noBody)
    self.handlers = prepareHandlers(handlers or {})
    if logger:isLoggable(logger.FINEST) then
      logger:finest('REST handlers')
      logger:finest(self.handlers)
    end
    --logger:logTable(logger.WARN, self.handlers)
    if type(attributes) == 'table' then
      self.attributes = attributes
    end
    self.consumeBody = noBody ~= true
  end

  function restHttpHandler:handleNow(exchange)
    local path = exchange:getRequestPath()
    local status, result = protectedCall(restPart, self.handlers, exchange, path)
    if status then
      if Promise.isPromise(result) then
        return result:next(function(r)
          processRestResponse(exchange, r)
          return true
        end)
      end
      processRestResponse(exchange, result)
    else
      if logger:isLoggable(logger.WARN) then
        logger:warn('REST handler error "'..tostring(result)..'"')
      end
      HttpExchange.internalServerError(exchange)
    end
  end

  function restHttpHandler:handle(exchange)
    if self.attributes then
      exchange:setAttributes(self.attributes)
    end
    if self.consumeBody then
      local request = exchange:getRequest()
      local length = request:getContentLength()
      if length and length > 0 then
        return exchange:onRequestBody(true):next(function()
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

  function RestHttpHandler.replyJson(exchange, t)
    local response = exchange:getResponse()
    response:setStatusCode(HttpMessage.CONST.HTTP_OK, 'OK')
    response:setContentType(HttpExchange.CONTENT_TYPES.json)
    response:setBody(json.stringify(t))
  end

  RestHttpHandler.restPart = restPart
  RestHttpHandler.shiftPath = shiftPath

  RestHttpHandler.REST_NOT_FOUND = REST_NOT_FOUND
  RestHttpHandler.REST_DONE = REST_DONE
  RestHttpHandler.REST_ANY = REST_ANY
  RestHttpHandler.REST_ALL = REST_ALL

end)
