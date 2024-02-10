local luaSocketLib = require('socket')

local logger = require('jls.lang.loggerFactory')(...)
local Promise = require('jls.lang.Promise')
local StreamHandler = require('jls.io.StreamHandler')
local Selector = require('jls.net.Selector-socket')

-- User Datagram Protocol

return require('jls.lang.class').create(function(udpSocket)

  function udpSocket:initialize(nds, selector)
    self.nds = nds
    self.selector = selector or Selector.DEFAULT
  end

  local luaSocketLib_udp4 = luaSocketLib.udp4 and luaSocketLib.udp4 or luaSocketLib.udp

  function udpSocket:create(addr, options)
    if self.nds == nil then
      if addr and string.find(addr, ':') or options and options.ipv6only == true then
        self.nds = luaSocketLib.udp6()
      else
        self.nds = luaSocketLib_udp4()
      end
    end
  end

  function udpSocket:bind(addr, port, options)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('udpSocket:bind('..tostring(addr)..', '..tostring(port)..')')
    end
    self:create(addr, options)
    if options and options.reuseaddr ~= nil then
      local status, err = self.nds:setoption('reuseaddr', options.reuseaddr)
      if not status then
        error('Error while enabling reuse address '..tostring(err))
      end
    end
    return self.nds:setsockname(addr, port)
  end

  function udpSocket:connect(addr, port)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('udpSocket:connect('..tostring(addr)..', '..tostring(port)..')')
    end
    return self.nds:setpeername(addr, port)
  end

  function udpSocket:disconnect()
    return self.nds:setpeername('*')
  end

  function udpSocket:getLocalName()
    if self.nds then
      return self.nds:getsockname() -- ip, port, family
    end
  end

  function udpSocket:getPort()
    if self.nds then
      return select(2, self.nds:getsockname())
    end
  end

  function udpSocket:setBroadcast(value)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('udpSocket:setBroadcast('..tostring(value)..')')
    end
    return self.nds:setoption('broadcast', value)
  end

  function udpSocket:setLoopbackMode(value)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('udpSocket:setLoopbackMode('..tostring(value)..')')
    end
    return self.nds:setoption('ip-multicast-loop', value)
  end

  function udpSocket:setTimeToLive(value)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('udpSocket:setTimeToLive('..tostring(value)..')')
    end
    return self.nds:setoption('ip-multicast-ttl', value)
  end

  function udpSocket:setInterface(value)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('udpSocket:setInterface('..tostring(value)..')')
    end
    return self.nds:setoption('ip-multicast-if', value)
  end

  function udpSocket:joinGroup(mcastaddr, ifaddr)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('udpSocket:joinGroup('..tostring(mcastaddr)..', '..tostring(ifaddr)..')')
    end
    return self.nds:setoption('ip-add-membership', {multiaddr = mcastaddr, interface = ifaddr})
  end

  function udpSocket:leaveGroup(mcastaddr, ifaddr)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('udpSocket:leaveGroup('..tostring(mcastaddr)..', '..tostring(ifaddr)..')')
    end
    return self.nds:setoption('ip-drop-membership', {multiaddr = mcastaddr, interface = ifaddr})
  end

  function udpSocket:receiveStart(cb)
    logger:debug('udpSocket:receiveStart(?)')
    local stream = StreamHandler.ensureStreamHandler(cb)
    if self.nds then
      self.selector:register(self.nds, nil, stream, nil, nil, true)
    else
      stream:onError('closed')
    end
  end

  function udpSocket:receiveStop()
    logger:debug('udpSocket:receiveStop()')
    if self.nds then
      self.selector:unregister(self.nds, Selector.MODE_RECV)
    end
  end

  function udpSocket:send(data, addr, port, callback)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('udpSocket:send('..tostring(string.len(data))..')')
    end
    local cb, d = Promise.ensureCallback(callback)
    self:create(addr)
    if self.nds then
      self.selector:register(self.nds, nil, nil, data, cb, addr, port)
    else
      cb('closed')
    end
    return d
  end

  function udpSocket:close(callback)
    logger:debug('udpSocket:close()')
    local cb, d = Promise.ensureCallback(callback)
    local nds = self.nds
    self.nds = false
    if nds then
      self.selector:close(nds, cb)
    else
      cb()
    end
    return d
  end
end)
