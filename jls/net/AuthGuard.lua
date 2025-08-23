--[[--
Protects a TCP server against unauthenticated connections.
The authentications on new IP are detected.
Bad authentications are monitored and user is blocked.
Connections attempts from IP without authentication are blocked.

@module jls.net.AuthGuard
@pragma nostrip
]]

local class = require('jls.lang.class')
local logger = require('jls.lang.logger'):get(...)
local system = require('jls.lang.system')

return class.create(function(authGuard)

  function authGuard:initialize()
    self.infoByUser = {}
    self.maxFailures = 5
    self.infoByIp = {}
    self.maxAttempts = 5
    self.maxShortAttempts = 15
    self.attemptDelay = 30
    self.cleanupDelay = 3600 * 24 * 7
    self.cleanupTime = system.currentTime() + self.cleanupDelay
  end

  function authGuard:acceptIp(ip)
    local time = system.currentTime()
    if time > self.cleanupTime then
      self:clean(time - self.cleanupDelay)
      self.cleanupTime = time + self.cleanupDelay
    end
    local info = self.infoByIp[ip]
    if info then
      if not info.granted then
        if info.attempts >= self.maxAttempts or info.shortAttempts >= self.maxShortAttempts then
          logger:fine('IP %s blocked', ip)
          return false
        end
        if time < info.time + self.attemptDelay then
          info.shortAttempts = info.shortAttempts + 1
        else
          info.attempts = info.attempts + 1
          info.shortAttempts = 0
          info.time = time
        end
      end
    else
      logger:fine('IP %s added', ip)
      self.infoByIp[ip] = {
        attempts = 0,
        shortAttempts = 0,
        since = time,
        time = time
      }
    end
    return true
  end

  function authGuard:clean(time)
    for ip, info in pairs(self.infoByIp) do
      if info.since < time then
        self.infoByIp[ip] = nil
      end
    end
    for user, info in pairs(self.infoByUser) do
      if info.since < time then
        self.infoByUser[user] = nil
      end
    end
  end

  function authGuard:grantIp(ip)
    local info = self.infoByIp[ip]
    if info and not info.granted then
      logger:fine('IP %s granted', ip)
      info.granted = true
    end
  end

  function authGuard:guard(server)
    if server then
      -- TODO use handleAccept and TcpSocket.prototype.getRemoteName(client)
      local onAccept = server.onAccept
      if type(onAccept) ~= 'function' then
        error('invalid server')
      end
      if not self.id then
        self.id = string.format('_ag_%p', self)
      end
      if server[self.id] then
        error('already exists')
      end
      server[self.id] = onAccept
      server.onAccept = function(s, client)
        local ip = client:getRemoteName()
        if ip and self:acceptIp(ip) then
          onAccept(s, client)
        else
          client:close()
        end
      end
    end
  end

  function authGuard:release(server)
    if server and self.id and server[self.id] then
      server.onAccept = server[self.id]
      server[self.id] = nil
    end
  end

  function authGuard:onIpGranted(user, ip)
  end

  function authGuard:onUserBlocked(user)
  end

  function authGuard:denyUser(user)
    local info = self.infoByUser[user]
    if info then
      local failures = (info.failures or 0) + 1
      info.failures = failures
      if failures >= self.maxFailures then
        info.blocked = true
        logger:fine('User %s blocked, too much failed authentications', user)
        self:onUserBlocked(user)
      end
    end
  end

  function authGuard:grantUser(user, exchange)
    local time = system.currentTime()
    local info = self.infoByUser[user]
    if not info then
      info = {
        ips = {},
        since = time
      }
      self.infoByUser[user] = info
    end
    if info.blocked then
      return false
    end
    local ip = exchange and exchange:getClient():getRemoteName()
    if ip then
      if not info.ips[ip] then
        logger:fine('IP %s granted for user %s', ip, user)
        self:onIpGranted(user, ip)
        info.ips[ip] = ip
      end
      self:grantIp(ip)
      info.time = time
    end
    return true
  end

end)
