--- This class represents an HTTP request.
-- @module jls.net.http.HttpRequest
-- @pragma nostrip

local HttpMessage = require('jls.net.http.HttpMessage')
local Date = require('jls.util.Date')

--- The HttpRequest class represents an HTTP request.
-- The HttpRequest class inherits from @{HttpMessage}.
-- @type HttpRequest
return require('jls.lang.class').create(HttpMessage, function(httpRequest, super)

  --- Creates a new Request.
  -- @function HttpRequest:new
  function httpRequest:initialize()
    super.initialize(self)
    self.method = ''
    self.target = '/'
  end

  function httpRequest:getMethod()
    return self.method
  end

  function httpRequest:setMethod(value)
    self.method = string.upper(value)
    self.line = ''
  end

  function httpRequest:getTarget()
    return self.target
  end

  function httpRequest:setTarget(value)
    self.target = value
    self.line = ''
  end

  function httpRequest:setVersion(version)
    self.line = ''
    return super.setVersion(self, version)
  end

  function httpRequest:getLine()
    if self.line == '' and self.method ~= '' then
      self.line = self.method..' '..self.target..' '..self:getVersion()
    end
    return self.line
  end

  function httpRequest:setLine(line)
    -- see https://tools.ietf.org/html/rfc7230#section-3.1.1
    local method, target, version = string.match(line, "^(%S+)%s(%S+)%s(HTTP/%d+%.%d+)$")
    if method then
      self.line = line
      self.method = string.upper(method)
      self.target = target
      self.version = version
      return true
    end
    self.line = ''
    self.method = ''
    self.target = ''
    self.version = ''
    return false
  end

  function httpRequest:getTargetPath()
    return string.gsub(self.target, '%?.*$', '')
  end

  function httpRequest:getTargetQuery()
    return string.gsub(self.target, '^[^%?]*%??', '')
  end

  function httpRequest:getIfModifiedSince()
    local value = self:getHeader('If-Modified-Since')
    if type(value) == 'string' then
      return Date.fromRFC822String(value)
    end
    return value
  end

end)
