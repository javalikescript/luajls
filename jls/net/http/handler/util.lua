local json = require('jls.util.json')
local Path = require('jls.io.Path')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST

local util = {}

local HTTP_CONTENT_TYPES = {
  bin = 'application/octet-stream',
  css = 'text/css',
  js = 'application/javascript',
  json = 'application/json',
  htm = 'text/html',
  html = 'text/html',
  txt = 'text/plain',
  xml = 'text/xml',
  pdf = 'application/pdf',
}

function util.replyJson(response, t)
  response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
  response:setContentType(HTTP_CONTENT_TYPES.json)
  response:setBody(json.encode(t))
end

--- Returns an handler that chain the specified handlers
function util.chain(...)
  local handlers = {...}
  return function(httpExchange)
    httpExchange:getResponse():setStatusCode(0)
    local result
    for _, handler in ipairs(handlers) do
      result = handler(httpExchange)
      if httpExchange:getResponse():getStatusCode() ~= 0 then
        break
      end
    end
    return result
  end
end

function util.isValidSubPath(path)
  -- Checks whether it starts, ends or contains /../
  return not (string.find(path, '/../', 1, true) or string.match(path, '^%.%./') or string.match(path, '/%.%.$') or string.find(path, '\\', 1, true))
  --return not string.find(path, '..', 1, true)
end

function util.shiftPath(path)
  return string.match(path, '^([^/]+)/?(.*)$')
end

local REST_NOT_FOUND = {}

local REST_ANY = '/any'
local REST_METHOD = '/method'

function util.restPart(handlers, httpExchange, path)
  local name, remainingPath = util.shiftPath(path)
  local handler
  if name then
    handler = handlers[REST_ANY]
    if handler then
      if type(handlers.name) == 'string' then
        local value = name
        if type(handlers.value) == 'function' then
          value = handlers.value(httpExchange, name)
        end
        if value == nil then
          return REST_NOT_FOUND
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
    return util.restPart(handler, httpExchange, remainingPath)
  elseif type(handler) == 'function' then
    httpExchange:setAttribute('path', remainingPath)
    return handler(httpExchange)
  end
  if path == 'names' then
    local names = {}
    for name in pairs(handlers) do
      table.insert(names, name)
    end
    return names
  end
  return REST_NOT_FOUND
end

function util.guessContentType(path, def)
  local extension
  if type(path) == 'string' then
    extension = Path.extractExtension(path)
  else
    extension = path:getExtension()
  end
  return HTTP_CONTENT_TYPES[extension] or def or HTTP_CONTENT_TYPES.bin
end

util.REST_NOT_FOUND = REST_NOT_FOUND
util.REST_ANY = REST_ANY
util.REST_METHOD = REST_METHOD

util.CONTENT_TYPES = HTTP_CONTENT_TYPES

return util
