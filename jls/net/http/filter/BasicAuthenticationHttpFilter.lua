--- Provide a simple HTTP filter for basic authentication.
-- @module jls.net.http.filter.BasicAuthenticationHttpFilter
-- @pragma nostrip

local logger = require('jls.lang.logger'):get(...)
local Codec = require('jls.util.Codec')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST

--- A BasicAuthenticationHttpFilter class.
-- @type BasicAuthenticationHttpFilter
return require('jls.lang.class').create('jls.net.http.HttpFilter', function(filter)

  local function checkAnyCredentials()
    return true
  end

  --- Creates a basic authentication @{HttpFilter}.
  -- @param checkCredentials a table with user name and password pairs or a function.
  -- @tparam[opt] string realm an optional message.
  -- @function BasicAuthenticationHttpFilter:new
  function filter:initialize(checkCredentials, realm)
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

  function filter:onAuthorizationFailed(exchange, user)
    logger:warn('basicAuthentication() user "%s" from %s is not authorized', user, exchange:clientAsString())
  end

  function filter:doFilter(exchange)
    local request = exchange:getRequest()
    local response = exchange:getResponse()
    local authorization = request:getHeader(HTTP_CONST.HEADER_AUTHORIZATION)
    if not authorization then
      response:setHeader(HTTP_CONST.HEADER_WWW_AUTHENTICATE, 'Basic realm="'..self.realm..'"')
      response:setStatusCode(HTTP_CONST.HTTP_UNAUTHORIZED, 'Unauthorized')
      return false
    end
    logger:finest('basicAuthentication() authorization: "%s"', authorization)
    if string.find(authorization, 'Basic ') == 1 then
      authorization = Codec.decode('base64', string.sub(authorization, 7))
      if authorization then
        local user, password = string.match(authorization, '^([^:]+):(.+)$')
        if user then
          if self.checkCredentials(user, password) then
            return
          end
          response:setHeader(HTTP_CONST.HEADER_WWW_AUTHENTICATE, 'Basic realm="'..self.realm..'"')
          response:setStatusCode(HTTP_CONST.HTTP_UNAUTHORIZED, 'Unauthorized')
          self:onAuthorizationFailed(exchange, user)
          return false
        end
      end
    end
    logger:warn('Bad authentication request from %s', exchange:clientAsString())
    response:setStatusCode(HTTP_CONST.HTTP_BAD_REQUEST, 'Bad request')
    return false
  end

end)
