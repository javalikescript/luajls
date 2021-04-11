--- This class represents an HTTP request.
-- @module jls.net.http.HttpRequest
-- @pragma nostrip

--- The HttpRequest class represents an HTTP request.
-- The HttpRequest class inherits from @{HttpMessage}.
-- @type HttpRequest
return require('jls.lang.class').create(require('jls.net.http.HttpMessage'), function(httpRequest, super)

  --- Creates a new Request.
  -- @function HttpRequest:new
  function httpRequest:initialize()
    super.initialize(self)
    self.method = 'GET'
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

  function httpRequest:getLine()
    if self.line == '' then
      self.line = self:getMethod()..' '..self:getTarget()..' '..self:getVersion()
      --self.line = table.concat({self:getMethod(), ' ', self:getTarget(), ' ', self:getVersion()})
    end
    return self.line
  end

  function httpRequest:setLine(line)
    self.line = line
    -- see https://tools.ietf.org/html/rfc7230#section-3.1.1
    local method, target, version = string.match(line, "^(%S+)%s(%S+)%s(%S+)$")
    if method then
      self.method = string.upper(method)
      self.target = target
      self.version = version
    else
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
