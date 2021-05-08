-- Deprecated, will be removed

local logger = require('jls.lang.logger')
local httpHandlerBase = require('jls.net.http.handler.base')
local httpHandlerUtil = require('jls.net.http.handler.util')
local json = require('jls.util.json')
local tables = require('jls.util.tables')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST

local function table(httpExchange)
  local request = httpExchange:getRequest()
  local context = httpExchange:getContext()
  local t = context:getAttribute('table')
  local p = context:getAttribute('path') or ''
  if not t then
    t = {}
    context:setAttribute('table', t)
  end
  local method = string.upper(request:getMethod())
  --local path = httpExchange:getRequest():getTarget()
  local path = httpExchange:getRequestArguments()
  local tp = p..string.gsub(path, '/$', '')
  if logger:isLoggable(logger.FINE) then
    logger:fine('httpHandler.table(), method: "'..method..'", path: "'..tp..'"')
  end
  -- TODO Handle HEAD as a GET without body
  if method == HTTP_CONST.METHOD_GET then
    local value = tables.getPath(t, tp)
    httpHandlerBase.ok(httpExchange, json.encode({
      --success = true,
      --path = path,
      value = value
    }), httpHandlerUtil.CONTENT_TYPES.json)
  elseif not context:getAttribute('editable') then
    httpHandlerBase.methodNotAllowed(httpExchange)
  elseif method == HTTP_CONST.METHOD_PUT or method == HTTP_CONST.METHOD_POST or method == HTTP_CONST.METHOD_PATCH then
    if logger:isLoggable(logger.FINEST) then
      logger:finest('httpHandler.table(), request body: "'..request:getBody()..'"')
    end
    if request:getBodyLength() > 0 then
      local rt = json.decode(request:getBody())
      if type(rt) == 'table' and rt.value then
        if method == HTTP_CONST.METHOD_PUT then
          tables.setPath(t, tp, rt.value)
        elseif method == HTTP_CONST.METHOD_POST then
          local value = tables.getPath(t, tp)
          if type(value) == 'table' then
            tables.setByPath(value, rt.value)
          end
        elseif method == HTTP_CONST.METHOD_PATCH then
          tables.mergePath(t, tp, rt.value)
        end
      end
    end
    httpHandlerBase.ok(httpExchange)
  elseif method == HTTP_CONST.METHOD_DELETE then
    tables.removePath(t, tp)
    httpHandlerBase.ok(httpExchange)
  else
    httpHandlerBase.methodNotAllowed(httpExchange)
  end
  if logger:isLoggable(logger.FINE) then
    logger:fine('httpHandler.table(), status: '..tostring(httpExchange:getResponse():getStatusCode()))
  end
end

return table
