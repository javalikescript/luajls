local logger = require('jls.lang.logger')
local base64 = require('jls.util.base64')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST

-- Deprecated, will be removed

local function basicAuthentication(httpExchange)
  local context = httpExchange:getContext()
  local checkCredentials = context:getAttribute('checkCredentials')
  if not checkCredentials then
    local credentials = context:getAttribute('credentials')
    if not credentials then
      logger:warn('basicAuthentication() missing credentials')
      credentials = {}
    end
    checkCredentials = function(user, password)
      return credentials[user] == password
    end
    context:setAttribute('checkCredentials', checkCredentials)
  end
  local request = httpExchange:getRequest()
  local response = httpExchange:getResponse()
  local authorization = request:getHeader(HTTP_CONST.HEADER_AUTHORIZATION)
  if not authorization then
    response:setHeader(HTTP_CONST.HEADER_WWW_AUTHENTICATE, 'Basic realm="User Visible Realm"')
    response:setStatusCode(HTTP_CONST.HTTP_UNAUTHORIZED, 'Unauthorized')
    return
  end
  if logger:isLoggable(logger.FINEST) then
    logger:finest('basicAuthentication() authorization: "'..authorization..'"')
  end
  if string.find(authorization, 'Basic ') == 1 then
    authorization = base64.decode(string.sub(authorization, 7))
    if authorization then
      local user, password = string.match(authorization, '^([^:]+):(.+)$')
      if user then
        if not checkCredentials(user, password) then
          response:setHeader(HTTP_CONST.HEADER_WWW_AUTHENTICATE, 'Basic realm="User Visible Realm"')
          response:setStatusCode(HTTP_CONST.HTTP_UNAUTHORIZED, 'Unauthorized')
          if logger:isLoggable(logger.FINE) then
            logger:fine('basicAuthentication() use "'..user..'" is not authorized')
          end
        end
        return
      end
    end
  end
  response:setStatusCode(HTTP_CONST.HTTP_BAD_REQUEST, 'Bad request')
end

return basicAuthentication
