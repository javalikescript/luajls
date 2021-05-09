--- Provide a simple HTTP filter for basic authentication.
-- @module jls.net.http.filter.BasicAuthenticationHttpFilter
-- @pragma nostrip

local logger = require('jls.lang.logger')
local base64 = require('jls.util.base64')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST

--- A BasicAuthenticationHttpFilter class.
-- @type BasicAuthenticationHttpFilter
return require('jls.lang.class').create('jls.net.http.HttpFilter', function(basicAuthenticationHttpFilter)

  local function checkAnyCredentials()
    return true
  end

  --- Creates a basic authentication @{HttpFilter}.
  -- @param checkCredentials a table with user name and password pairs or a function.
  -- @tparam[opt] string realm an optional message.
  function basicAuthenticationHttpFilter:initialize(checkCredentials, realm)
    if type(checkCredentials) == 'function' then
      self.checkCredentials = checkCredentials
    elseif type(checkCredentials) == 'table' then
      self.checkCredentials = function(user, password)
        return checkCredentials[user] == password
      end
    else
      self.checkCredentials = checkAnyCredentials
    end
    self.realm = realm or 'User Visible Realm'
  end

  function basicAuthenticationHttpFilter:doFilter(httpExchange)
    local request = httpExchange:getRequest()
    local response = httpExchange:getResponse()
    local authorization = request:getHeader(HTTP_CONST.HEADER_AUTHORIZATION)
    if not authorization then
      response:setHeader(HTTP_CONST.HEADER_WWW_AUTHENTICATE, 'Basic realm="'..self.realm..'"')
      response:setStatusCode(HTTP_CONST.HTTP_UNAUTHORIZED, 'Unauthorized')
      return false
    end
    if logger:isLoggable(logger.FINEST) then
      logger:finest('basicAuthentication() authorization: "'..authorization..'"')
    end
    if string.find(authorization, 'Basic ') == 1 then
      authorization = base64.decode(string.sub(authorization, 7))
      if authorization then
        local user, password = string.match(authorization, '^([^:]+):(.+)$')
        if user then
          if self.checkCredentials(user, password) then
            return
          end
          response:setHeader(HTTP_CONST.HEADER_WWW_AUTHENTICATE, 'Basic realm="'..self.realm..'"')
          response:setStatusCode(HTTP_CONST.HTTP_UNAUTHORIZED, 'Unauthorized')
          if logger:isLoggable(logger.FINE) then
            logger:fine('basicAuthentication() user "'..user..'" is not authorized')
          end
          return false
        end
      end
    end
    response:setStatusCode(HTTP_CONST.HTTP_BAD_REQUEST, 'Bad request')
    return false
  end

end)
