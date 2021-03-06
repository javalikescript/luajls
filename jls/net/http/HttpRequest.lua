--- This class represents an HTTP request.
-- @module jls.net.http.HttpRequest
-- @pragma nostrip

--- The HttpRequest class represents an HTTP request.
-- The HttpRequest class inherits from @{HttpMessage}.
-- @type HttpRequest
return require('jls.lang.class').create('jls.net.http.HttpMessage', function(httpRequest, super)

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
    local method, target, version = string.match(line, "^(%S+)%s(%S+)%s(%S+)$")
    if method then
      self.line = line
      self.method = string.upper(method)
      self.target = target
      self.version = version
    else
      self.line = ''
      self.method = ''
      self.target = ''
      self.version = ''
    end
  end

  function httpRequest:getTargetPath()
    return string.gsub(self.target, '%?.*$', '')
  end

  function httpRequest:getTargetQuery()
    return string.gsub(self.target, '^[^%?]*%??', '')
  end

end)
