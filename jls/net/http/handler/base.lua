local HttpExchange = require('jls.net.http.HttpExchange')

-- Deprecated, will be removed

return {
  ok = HttpExchange.ok,
  badRequest = HttpExchange.badRequest,
  forbidden = HttpExchange.forbidden,
  notFound = HttpExchange.notFound,
  methodNotAllowed = HttpExchange.methodNotAllowed,
  internalServerError = HttpExchange.internalServerError,
  response = HttpExchange.response,
  methodAllowed = HttpExchange.methodAllowed,
}
