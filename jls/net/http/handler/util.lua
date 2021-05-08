local HttpExchange = require('jls.net.http.HttpExchange')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local RestHttpHandler = require('jls.net.http.handler.RestHttpHandler')

-- Deprecated, will be removed

return {
  replyJson = RestHttpHandler.replyJson,
  isValidSubPath = HttpExchange.isValidSubPath,
  shiftPath = RestHttpHandler.shiftPath,
  restPart = RestHttpHandler.restPart,
  REST_NOT_FOUND = RestHttpHandler.REST_NOT_FOUND,
  REST_ANY = RestHttpHandler.REST_ANY,
  REST_METHOD = '/method',
  CONTENT_TYPES = HttpExchange.CONTENT_TYPES,
  guessContentType = FileHttpHandler.guessContentType,
  chain = function(...)
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
  end,
}
