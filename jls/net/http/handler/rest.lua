-- Deprecated, will be removed

local json = require('jls.util.json')
local httpHandlerBase = require('jls.net.http.handler.base')
local httpHandlerUtil = require('jls.net.http.handler.util')

local function rest(httpExchange)
  local context = httpExchange:getContext()
  local handlers = context:getAttribute('handlers')
  if not handlers then
    httpHandlerBase.internalServerError(httpExchange)
    return
  end
  local attributes = context:getAttribute('attributes')
  if attributes and type(attributes) == 'table' then
    httpExchange:setAttributes(attributes)
  end
  -- if there is a request body with json content type then decode it
  --[[local request = httpExchange:getRequest()
  if request:getBody() and request:getHeader(HTTP_CONST.HEADER_CONTENT_TYPE) == httpHandlerUtil.CONTENT_TYPES.json then
    local rt = json.decode(request:getBody())
    httpExchange:setAttribute('body', rt)
  end]]
  local path = httpExchange:getRequestArguments()
  local body = httpHandlerUtil.restPart(handlers, httpExchange, path)
  if body == nil then
    httpHandlerBase.ok(httpExchange)
  elseif body == httpHandlerUtil.REST_NOT_FOUND then
    httpHandlerBase.notFound(httpExchange)
  elseif type(body) == 'string' then
    httpHandlerBase.ok(httpExchange, body, httpHandlerUtil.CONTENT_TYPES.txt)
  elseif type(body) == 'table' then
    httpHandlerBase.ok(httpExchange, json.encode(body), httpHandlerUtil.CONTENT_TYPES.json)
  elseif body == false then
    -- response by handler
  else
    httpHandlerBase.internalServerError(httpExchange)
  end
end

return rest
