--- redirect handler
local logger = require('jls.lang.logger')
local HttpClient = require('jls.net.http.HttpClient')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST

--- Proxies requests.
-- The requests are redirected to attribute url.
-- @tparam jls.net.http.HttpExchange httpExchange ongoing HTTP exchange
-- @function redirect
local function redirect(httpExchange)
  local request = httpExchange:getRequest()
  local response = httpExchange:getResponse()
  local context = httpExchange:getContext()
  local url = context:getAttribute('url') or ''
  local path = httpExchange:getRequestArguments()
  url = url..path
  logger:debug('redirecting to "'..url..'"')
  local client = HttpClient:new({
    url = url,
    method = request:getMethod(),
    headers = request:getHeaders()
  })
  return client:connect():next(function()
    logger:debug('httpHandler.redirect() connected')
    return client:sendReceive()
  end):next(function(subResponse)
    logger:debug('redirect client status code is '..tostring(subResponse:getStatusCode()))
    response:setStatusCode(subResponse:getStatusCode())
    response:setHeaders(subResponse:getHeaders())
    if subResponse:hasBody() then
      response:setBody(subResponse:getBody())
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
