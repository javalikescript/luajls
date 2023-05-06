--[[-- Provide a simple HTTP filter for session.

This filter add a session id cookie to the response and maintain the exchange session.

@module jls.net.http.filter.SessionHttpFilter
@pragma nostrip
]]

local system = require('jls.lang.system')
local HttpSession = require('jls.net.http.HttpSession')

--- A SessionHttpFilter class.
-- @type SessionHttpFilter
return require('jls.lang.class').create('jls.net.http.HttpFilter', function(sessionHttpFilter)

  --- Creates a basic session @{HttpFilter}.
  function sessionHttpFilter:initialize(name, maxAge)
    self.name = name or 'jls-session-id'
    self.maxAge = maxAge or 43200 -- 12 hours in seconds
    self.sessions = {}
    self.options = {
      'max-age='..tostring(self.maxAge),
      'HttpOnly',
      'SameSite=Strict'
    }
    self.time = system.currentTimeMillis()
    self.index = math.random(0xffff)
  end

  function sessionHttpFilter:cleanup(time)
    local creationTime = time - self.maxAge * 1000
    for sessionId, session in pairs(self.sessions) do
      if session:getCreationTime() < creationTime then
        self.sessions[sessionId] = nil
      end
    end
  end

  function sessionHttpFilter:generateId()
    self.index = (self.index + 1) & 0xffff
    return string.format('%08x-%04x-%04x-%08x', self.time, self.index, math.random(0xffff), math.random(0xffffffff))
  end

  function sessionHttpFilter:doFilter(exchange)
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
      self.sessions[sessionId] = session
      local response = exchange:getResponse()
      response:setCookie(self.name, sessionId, self.options)
    end
    session:setLastAccessTime(time)
    exchange:setSession(session)
  end

  function sessionHttpFilter:close()
    -- close cleanup scheduler
    self.sessions = {}
  end

end)
