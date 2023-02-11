local luaSocketLib = require('socket')

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local StreamHandler = require('jls.io.StreamHandler')
local Selector = require('jls.net.Selector-socket')

return require('jls.lang.class').create(function(tcpSocket, _, TcpSocket)
  function tcpSocket:initialize(socket, selector)
    self.tcp = socket
    self.selector = selector or Selector.DEFAULT
  end

  function tcpSocket:getLocalName()
    --logger:debug('tcpSocket:getLocalName()')
    return self.tcp:getsockname()
  end

  function tcpSocket:getRemoteName()
    --logger:debug('tcpSocket:getRemoteName()')
    return self.tcp:getPeerName()
  end

  function tcpSocket:isClosed()
    return not self.tcp
  end

  function tcpSocket:close(callback)
    logger:debug('tcp:close()')
    local cb, d = Promise.ensureCallback(callback)
    local socket = self.tcp
    if socket then
      self.tcp = nil
      self.selector:close(socket, cb)
    else
      cb()
    end
    return d
  end

  function tcpSocket:connect(addr, port, callback)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('tcpSocket:connect('..tostring(addr)..', '..tostring(port)..')')
    end
    local tcp, err = luaSocketLib.connect(addr or '127.0.0.1', port)
    self.tcp = tcp
    local cb, d = Promise.ensureCallback(callback)
    if err then
      if logger:isLoggable(logger.DEBUG) then
        logger:debug('tcpSocket:connect('..tostring(addr)..', '..tostring(port)..') error => "'..tostring(err)..'"')
      end
      cb(err)
    else
      cb(nil, self)
    end
    return d, err
  end

  function tcpSocket:write(data, callback)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('tcpSocket:write('..tostring(string.len(data))..')')
    end
    local cb, d = Promise.ensureCallback(callback)
    local req, err
    if self.tcp then
      req = self.selector:register(self.tcp, nil, nil, data, cb)
    else
      err = 'closed'
      cb(err)
    end
    return d, req, err
  end

  function tcpSocket:readStart(cb)
    logger:debug('tcpSocket:readStart(?)')
    local stream = StreamHandler.ensureStreamHandler(cb)
    local err
    if self.tcp then
      self.selector:register(self.tcp, nil, stream)
    else
      err = 'closed'
      stream:onError(err)
    end
    return not err, err
  end

  function tcpSocket:readStop()
    logger:debug('tcpSocket:readStop()')
    local err
    if self.tcp then
      self.selector:unregister(self.tcp, Selector.MODE_RECV)
    else
      err = 'closed'
    end
    return not err, err
  end

  function tcpSocket:setTcpNoDelay(on)
    logger:debug('tcpSocket:setTcpNoDelay('..tostring(on)..')')
    return self.tcp:setoption('tcp-nodelay', on)
  end

  function tcpSocket:setKeepAlive(on, delay)
    logger:debug('tcpSocket:setKeepAlive('..tostring(on)..', '..tostring(delay)..')')
    return self.tcp:setoption('keepalive', on)
  end

  function tcpSocket:bind(addr, port, backlog, callback)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('tcpSocket:bind('..tostring(addr)..', '..tostring(port)..')')
    end
    if not addr or addr == '0.0.0.0' or addr == '::' then
      addr = '*'
    end
    local cb, d = Promise.ensureCallback(callback)
    local tcp, err = luaSocketLib.bind(addr, port, backlog)
    if err then
      cb(err)
      return d
    end
    tcp:settimeout(0) -- do not block
    -- TODO Bind on IPv4 and IPv6
    self.tcp = tcp
    local server = self
    self.selector:register(self.tcp, Selector.MODE_RECV, function()
      server:handleAccept()
    end)
    cb()
    return d
  end

  function tcpSocket:handleAccept()
    local tcp = self:tcpAccept()
    if tcp then
      if logger:isLoggable(logger.DEBUG) then
        logger:debug('tcpSocket:handleAccept() accepting '..Selector.socketToString(tcp))
      end
      local client = TcpSocket:new(tcp)
      self:onAccept(client)
    else
      logger:debug('tcpSocket:handleAccept() accept error')
    end
  end

  function tcpSocket:tcpAccept()
    return self.tcp:accept()
  end

  function tcpSocket:onAccept(client)
    client:close()
  end

  TcpSocket.socketToString = Selector.socketToString

end)
