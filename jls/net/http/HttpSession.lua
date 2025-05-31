--[[--
HTTP session class.

A session is associated to the HTTP exchange.
It can be used for tasks such as authentication, access control.

@module jls.net.http.HttpSession
@pragma nostrip
]]

--- A HttpSession class.
-- The HttpSession class inherits from @{Attributes}.
-- @type HttpSession
return require('jls.lang.class').create('jls.net.http.Attributes', function(httpSession, super)

  --- Creates an HTTP session.
  -- @function HttpSession:new
  function httpSession:initialize(id, creationTime)
    super.initialize(self)
    self.id = id or ''
    self.creationTime = creationTime or 0
    self.lastAccessTime = self.creationTime
  end

  --- Returns this session id.
  -- @treturn string the session id.
  function httpSession:getId()
    return self.id
  end

  --- Returns the creation time of this session.
  -- The time is given as the number of milliseconds since the Epoch, 1970-01-01 00:00:00 +0000 (UTC). 
  -- @treturn number the creation time.
  function httpSession:getCreationTime()
    return self.creationTime
  end

  --- Returns the time where this session was last accessed.
  -- The time is given as the number of milliseconds since the Epoch, 1970-01-01 00:00:00 +0000 (UTC). 
  -- @treturn number the last access time.
  function httpSession:getLastAccessTime()
    return self.lastAccessTime
  end

  function httpSession:setLastAccessTime(time)
    self.lastAccessTime = time
  end

  --- Invalidates this session.
  function httpSession:invalidate()
    self.id = ''
    self.creationTime = 0
    self.lastAccessTime = 0
    self:cleanAttributes()
  end

  function httpSession:serialize(write)
    write(self.id)
    write(self.creationTime)
    write(self.lastAccessTime)
    for name, value in pairs(self:getAttributes()) do
      write(name)
      if not write(value, true) then
        write(nil)
      end
    end
    write(nil)
  end

  function httpSession:deserialize(read)
    super.initialize(self)
    self.id = read('string')
    self.creationTime = read('number')
    self.lastAccessTime = read('number')
    while true do
      local name = read('string|nil')
      if name then
        local value = read()
        if value ~= nil then
          self:setAttribute(name, value)
        end
      else
        break
      end
    end
  end

end)
