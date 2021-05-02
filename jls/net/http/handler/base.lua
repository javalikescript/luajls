--- basic handlers.
-- @module jls.net.http.handler.base
-- @pragma nostrip

local HTTP_CONST = require('jls.net.http.HttpMessage').CONST

local base = {}

--- Updates the response with the OK status code, 200.
-- @tparam jls.net.http.HttpExchange httpExchange ongoing HTTP exchange
-- @tparam[opt] string body the response content.
-- @tparam[opt] string contentType the response content type.
function base.ok(httpExchange, body, contentType)
  local response = httpExchange:getResponse()
  response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
  if type(contentType) == 'string' then
    response:setContentType(contentType)
  end
  if body then
    response:setBody(body)
  end
end

--- Updates the response with the status code Bad Request, 400.
-- @tparam jls.net.http.HttpExchange httpExchange ongoing HTTP exchange
function base.badRequest(httpExchange)
  httpExchange:setResponseStatusCode(HTTP_CONST.HTTP_BAD_REQUEST, 'Bad Request', '<p>Sorry something seems to be wrong in your request.</p>')
end

--- Updates the response with the status code Forbidden, 403.
-- @tparam jls.net.http.HttpExchange httpExchange ongoing HTTP exchange
function base.forbidden(httpExchange)
  httpExchange:setResponseStatusCode(HTTP_CONST.HTTP_FORBIDDEN, 'Forbidden', '<p>The server cannot process your request.</p>')
end

--- Updates the response with the status code Not Found, 404.
-- @tparam jls.net.http.HttpExchange httpExchange ongoing HTTP exchange
function base.notFound(httpExchange)
  httpExchange:setResponseStatusCode(HTTP_CONST.HTTP_NOT_FOUND, 'Not Found', '<p>The resource "'..httpExchange:getRequest():getTarget()..'" is not available.</p>')
end

--- Updates the response with the status code Method Not Allowed, 405.
-- @tparam jls.net.http.HttpExchange httpExchange ongoing HTTP exchange
function base.methodNotAllowed(httpExchange)
  httpExchange:setResponseStatusCode(HTTP_CONST.HTTP_METHOD_NOT_ALLOWED, 'Method Not Allowed', '<p>Sorry this method is not allowed.</p>')
end

--- Updates the response with the status code Internal Server Error, 500.
-- @tparam jls.net.http.HttpExchange httpExchange ongoing HTTP exchange
function base.internalServerError(httpExchange)
  local response = httpExchange:getResponse()
  response:setVersion(HTTP_CONST.VERSION_1_0)
  response:setStatusCode(HTTP_CONST.HTTP_INTERNAL_SERVER_ERROR, 'Internal Server Error')
  response:setBody('<p>Sorry something went wrong on our side.</p>')
end

--- Updates the response with the allowed methods.
-- @tparam jls.net.http.HttpExchange httpExchange ongoing HTTP exchange
function base.options(httpExchange, ...)
  local response = httpExchange:getResponse()
  response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
  response:setHeader('Allow', table.concat({HTTP_CONST.METHOD_OPTIONS, ...}, ', '))
  response:setBody('')
end

function base.response(httpExchange, statusCode, reasonPhrase, body)
  httpExchange:setResponseStatusCode(statusCode or HTTP_CONST.HTTP_OK, reasonPhrase or 'OK', body or '')
end

function base.isMethodAllowed(httpExchange, method)
  local requestMethod = httpExchange:getRequestMethod()
  if type(method) == 'string' then
    if requestMethod == method then
      return true
    end
  elseif type(method) == 'table' then
    for _, m in ipairs(method) do
      if requestMethod == m then
        return true
      end
    end
  end
  return false
end

function base.methodAllowed(httpExchange, method)
  if base.isMethodAllowed(httpExchange, method) then
    return true
  end
  base.methodNotAllowed(httpExchange)
  return false
end

return base
