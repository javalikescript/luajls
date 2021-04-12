--- redirect handler
local logger = require('jls.lang.logger')
local StringBuffer = require('jls.lang.StringBuffer')
local HttpClient = require('jls.net.http.HttpClient')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST

local function messageToString(message)
  local buffer = StringBuffer:new()
  buffer:append(message:getLine(), '\n')
  for name, value in pairs(message:getHeadersTable()) do
    buffer:append('  ', name, ': ', tostring(value), '\n')
  end
  buffer:append('\n', message:getBody(), '\n')
  return buffer:toString()
end

--- Proxies requests.
-- The requests are redirected to attribute url.
-- @tparam jls.net.http.HttpExchange httpExchange ongoing HTTP exchange
-- @function redirect
local function redirect(httpExchange)
  local request = httpExchange:getRequest()
  local response = httpExchange:getResponse()
  local context = httpExchange:getContext()
  local url = context:getAttribute('url') or ''
  local log = context:getAttribute('log') or false
  local path = httpExchange:getRequestArguments()
  url = url..path
  if logger:isLoggable(logger.FINE) then
    logger:fine('redirecting to "'..url..'"')
  end
  local client = HttpClient:new({
    url = url,
    method = request:getMethod(),
    headers = request:getHeadersTable(),
    body = request:hasBody() and request:getBody() or nil
  })
  if log and logger:isLoggable(logger.INFO) then
    logger:info('redirect request')
    logger:info(messageToString(request))
  end
  return client:connect():next(function()
    logger:debug('httpHandler.redirect() connected')
    return client:sendReceive()
  end):next(function(subResponse)
    if logger:isLoggable(logger.FINE) then
      logger:fine('redirect client status code is '..tostring(subResponse:getStatusCode()))
    end
    response:setStatusCode(subResponse:getStatusCode())
    response:setHeadersTable(subResponse:getHeadersTable())
    if subResponse:hasBody() then
      response:setBody(subResponse:getBody())
    end
    if log and logger:isLoggable(logger.INFO) then
      logger:info('redirect response')
      logger:info(messageToString(subResponse))
    end
    client:close()
  end, function(err)
    logger:debug('redirect error: '..tostring(err))
    response:setStatusCode(HTTP_CONST.HTTP_INTERNAL_SERVER_ERROR, 'Internal Server Error')
    response:setBody('<p>Sorry something went wrong on our side.</p>')
    client:close()
  end)
end

return redirect
