--- Provide a simple HTTP filter for session.
-- @module jls.net.http.filter.SessionHttpFilter
-- @pragma nostrip

local class = require('jls.lang.class')
local system = require('jls.lang.system')
local HttpSession = require('jls.net.http.HttpSession')

--- A SessionHttpFilter class.
-- @type SessionHttpFilter
return class.create('jls.net.http.HttpFilter', function(filter)

  --- Creates a basic session @{HttpFilter}.
  -- This filter adds a session id cookie to the response and maintain the exchange session.
  -- @tparam[opt] number maxAge the session max age in seconds, default to 12 hours.
  -- @tparam[opt] number idleTimeout the session idle timeout in seconds, default to maxAge.
  -- @function SessionHttpFilter:new
  function filter:initialize(maxAge, idleTimeout)
    self.name = 'jls-session-id'
    self.maxAge = maxAge or 43200 -- 12 hours in seconds
    self.idleTimeout = idleTimeout or self.maxAge
    self.sessions = {}
    self.options = {
      'max-age='..tostring(self.maxAge),
      'HttpOnly',
      'SameSite=Strict'
    }
    self.id = system.currentTimeMillis() & 0xffffffff
  end

  function filter:generateId()
    local sessionId
    repeat
      sessionId = string.format('%012x-%08x', math.random(0, 0xffffffffffff), self.id)
    until not self.sessions[sessionId]
    return sessionId
  end

  function filter:onCreated(session)
  end

  function filter:onDestroyed(session)
  end

  --- Removes the invalid sessions.
  -- @tparam[opt] number time the reference time to compute the age of the session.
  function filter:cleanup(time)
    time = time or system.currentTimeMillis()
    local creationTime = time - self.maxAge * 1000
    local lastAccessTime = time - self.idleTimeout * 1000
    for sessionId, session in pairs(self.sessions) do
      if session:getCreationTime() < creationTime or session:getLastAccessTime() < lastAccessTime then
        self.sessions[sessionId] = nil
        self:onDestroyed(session)
      end
    end
  end

  function filter:doFilter(exchange)
    local time = system.currentTimeMillis()
    self:cleanup(time)
    local request = exchange:getRequest()
    local sessionId = request:getCookie(self.name)
    local session
    if sessionId then
      session = self.sessions[sessionId]
    end
    if not session then
      sessionId = self:generateId()
      session = HttpSession:new(sessionId, time)
      self:onCreated(session)
      self.sessions[sessionId] = session
      local response = exchange:getResponse()
      response:setCookie(self.name, sessionId, self.options)
    end
    session:setLastAccessTime(time)
    exchange:setSession(session)
  end

  function filter:close()
    for _, session in pairs(self.sessions) do
      self:onDestroyed(session)
    end
    self.sessions = {}
  end

end)
