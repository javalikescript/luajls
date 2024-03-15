local luaSocketLib = require('socket')

local logger = require('jls.lang.logger'):get(...)
local Promise = require('jls.lang.Promise')
local StreamHandler = require('jls.io.StreamHandler')
local Selector = require('jls.net.Selector-socket')

return require('jls.lang.class').create(function(tcpSocket, _, TcpSocket)

  function tcpSocket:initialize(socket, selector)
    self.tcp = socket
    self.selector = selector or Selector.DEFAULT
    logger:finer('initialize() %s', self)
  end

  function tcpSocket:toString()
    if self.tcp then
      local status, ip, port = pcall(self.tcp.getpeername, self.tcp) -- unconnected udp fails
      if status and ip then
        return string.format('%s; %s:%s', self.tcp, ip, port)
      end
    end
    return 'unbounded tcp socket'
  end

  function tcpSocket:getLocalName()
    return self.tcp:getsockname()
  end

  function tcpSocket:getRemoteName()
    return self.tcp:getPeerName()
  end

  function tcpSocket:isClosed()
    return not self.tcp
  end

  function tcpSocket:close(callback)
    logger:finer('close()')
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
    logger:finer('connect(%s, %s)', addr, port)
    local tcp, err = luaSocketLib.connect(addr or '127.0.0.1', port)
    self.tcp = tcp
    local cb, d = Promise.ensureCallback(callback)
    if err then
      logger:finer('connect(%s, %s) error => "%s"', addr, port, err)
      cb(err)
    else
      cb(nil, self)
    end
    return d, err
  end

  function tcpSocket:write(data, callback)
    logger:finer('write(%s)', data and #data)
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
    logger:finer('readStart(?)')
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
    logger:finer('readStop()')
    local err
    if self.tcp then
      self.selector:unregister(self.tcp, Selector.MODE_RECV)
    else
      err = 'closed'
    end
    return not err, err
  end

  function tcpSocket:setTcpNoDelay(on)
    logger:finer('setTcpNoDelay(%s)', on)
    return self.tcp:setoption('tcp-nodelay', on)
  end

  function tcpSocket:setKeepAlive(on, delay)
    logger:finer('setKeepAlive(%s, %s)', on, delay)
    return self.tcp:setoption('keepalive', on)
  end

  function tcpSocket:bind(addr, port, backlog, callback)
    logger:finer('bind(%s, %s)', addr, port)
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
      logger:finer('accepting %s', tcp)
      local client = TcpSocket:new(tcp)
      self:onAccept(client)
    else
      logger:finer('accept error')
    end
  end

  function tcpSocket:tcpAccept()
    return self.tcp:accept()
  end

  function tcpSocket:onAccept(client)
    logger:warn('closing on accept')
    client:close()
  end

end)
