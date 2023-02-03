--- This class represents an HTTP response.
-- @module jls.net.http.HttpResponse
-- @pragma nostrip

local HttpMessage = require('jls.net.http.HttpMessage')
local Date = require('jls.util.Date')
local HTTP_CONST = HttpMessage.CONST

--- The HttpResponse class represents an HTTP response.
-- The HttpResponse class inherits from @{HttpMessage}.
-- @type HttpResponse
return require('jls.lang.class').create(HttpMessage, function(httpResponse, super)

  --- Creates a new Response.
  -- @function HttpResponse:new
  function httpResponse:initialize()
    super.initialize(self)
    self:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
  end

  --- Returns this HTTP response status code.
  -- @treturn string the HTTP response status code.
  function httpResponse:getStatusCode()
    return self.statusCode, self.reasonPhrase
  end

  --- Returns this HTTP response reason phrase.
  -- @treturn string the HTTP response reason phrase.
  function httpResponse:getReasonPhrase()
    return self.reasonPhrase
  end

  --- Sets the status code for the response.
  -- @tparam number statusCode the status code.
  -- @tparam[opt] string reasonPhrase the reason phrase.
  function httpResponse:setStatusCode(statusCode, reasonPhrase)
    self.statusCode = tonumber(statusCode)
    if type(reasonPhrase) == 'string' then
      self.reasonPhrase = reasonPhrase
    end
    self.line = ''
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
    local version, statusCode, reasonPhrase = string.match(line, "^(HTTP/%d+%.%d+)%s(%d+)%s(.*)$")
    if version then
      self.version = version
      self.statusCode = tonumber(statusCode)
      self.reasonPhrase = reasonPhrase
      return true
    end
    self.version = ''
    self.statusCode = 0
    self.reasonPhrase = ''
    return false
  end

  function httpResponse:setContentType(value)
    self:setHeader(HTTP_CONST.HEADER_CONTENT_TYPE, value)
  end

  function httpResponse:setCacheControl(value)
    if type(value) == 'boolean' then
      value = value and 604800 or -1 -- one week
    end
    if type(value) == 'number' then
      if value >= 0 then
        value = 'public, max-age='..tostring(value)..', must-revalidate'
      else
        value = 'no-store, no-cache, must-revalidate'
      end
    elseif type(value) ~= 'string' then
      error('Invalid cache control value')
    end
    self:setHeader(HTTP_CONST.HEADER_CACHE_CONTROL, value)
  end

  function httpResponse:setLastModified(value)
    -- All HTTP date/time stamps MUST be represented in Greenwich Mean Time (GMT)
    if type(value) == 'number' then
      value = Date:new(value):toRFC822String(true)
    elseif Date:isInstance(value) then
      value = value:toRFC822String(true)
    end
    self:setHeader(HTTP_CONST.HEADER_LAST_MODIFIED, value)
  end

end)
