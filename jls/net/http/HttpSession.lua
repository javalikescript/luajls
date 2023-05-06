--[[--
HTTP session class.

A session is associated to the HTTP exchange.
It can be used for tasks such as authentication, access control.

@module jls.net.http.HttpSession
@pragma nostrip
]]

--- A HttpSession class.
-- @type HttpSession
return require('jls.lang.class').create('jls.net.http.Attributes', function(httpSession, super)

  --- Creates an HTTP session.
  -- @function HttpSession:new
  function httpSession:initialize(id, creationTime)
    super.initialize(self)
    self.id = id or ''
    self.creationTime = creationTime or 0
    self.lastAccessTime = 0
  end

  function httpSession:getId()
    return self.id
  end

  function httpSession:getCreationTime()
    return self.creationTime
  end

  function httpSession:getLastAccessTime()
    return self.lastAccessTime
  end

  function httpSession:setLastAccessTime(time)
    self.lastAccessTime = time
  end

end)
