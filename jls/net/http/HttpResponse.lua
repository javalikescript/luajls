--- This class represents an HTTP response.
-- @module jls.net.http.HttpResponse
-- @pragma nostrip

local HttpMessage = require('jls.net.http.HttpMessage')

--- The HttpResponse class represents an HTTP response.
-- The HttpResponse class inherits from @{HttpMessage}.
-- @type HttpResponse
return require('jls.lang.class').create(HttpMessage, function(httpResponse, super)

  --- Creates a new Response.
  -- @function HttpResponse:new
  function httpResponse:initialize()
    super.initialize(self)
    self:setStatusCode(HttpMessage.CONST.HTTP_OK, 'OK')
    --self:setBody('')
    --self:setHeader(HttpMessage.CONST.HEADER_CONNECTION, HttpMessage.CONST.CONNECTION_CLOSE)
    --self:setHeader(HttpMessage.CONST.HEADER_SERVER, HttpMessage.CONST.DEFAULT_SERVER)
    --self:setHeader(HttpMessage.CONST.HEADER_CONTENT_TYPE, 'text/html; charset=utf-8')
    --self:setHeader(HttpMessage.CONST.HEADER_CONTENT_LENGTH], '0')
  end

  function httpResponse:getStatusCode()
    return self.statusCode, self.reasonPhrase
  end

  function httpResponse:setStatusCode(statusCode, reasonPhrase)
    self.statusCode = tonumber(statusCode)
    if type(reasonPhrase) == 'string' then
      self.reasonPhrase = reasonPhrase
    end
    self.line = ''
  end

  function httpResponse:getReasonPhrase()
    return self.reasonPhrase
  end

  function httpResponse:setReasonPhrase(value)
    self.reasonPhrase = value
    self.line = ''
  end

  function httpResponse:setVersion(value)
    self.version = value
    self.line = ''
  end

  function httpResponse:getLine()
    if self.line == '' then
      self.line = self:getVersion()..' '..tostring(self:getStatusCode())..' '..self:getReasonPhrase()
      --self.line = table.concat({self:getVersion(), ' ', self:getStatusCode(), ' ', self:getReasonPhrase()})
    end
    return self.line
  end

  function httpResponse:setLine(line)
    self.line = line
    -- see https://tools.ietf.org/html/rfc7230#section-3.1.1
    local index, _, version, statusCode, reasonPhrase = string.find(line, "(%S+)%s(%S+)%s(%S+)")
    if index then
      self.version = version
      self.statusCode = tonumber(statusCode)
      self.reasonPhrase = reasonPhrase
    end
  end

  function httpResponse:setContentType(value)
    self:setHeader(HttpMessage.CONST.HEADER_CONTENT_TYPE, value)
  end

  function httpResponse:setCacheControl(value)
    if type(value) == 'boolean' then
      if value then
        value = 'public, max-age=31536000'
      else
        value = 'no-cache, no-store, must-revalidate'
      end
    elseif type(value) == 'number' then
      value = 'public, max-age='..tostring(value)
    end
    self:setHeader(HttpMessage.CONST.HEADER_CACHE_CONTROL, value)
  end
end)
