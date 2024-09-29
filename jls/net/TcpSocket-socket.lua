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
        return string.format('tcpSocket: %p; %s:%s', self, ip, port)
      end
    end
    return string.format('tcpSocket: %p; unbounded', self)
  end

  function tcpSocket:getLocalName()
    return self.tcp:getsockname()
  end

  function tcpSocket:getRemoteName()
    return self.tcp:getpeername()
  end

  function tcpSocket:isClosed()
    return not self.tcp
  end

  function tcpSocket:close(callback)
    logger:finer('close()')
    local cb, d = Promise.ensureCallback(callback)
    local tcp = self.tcp
    if tcp then
      self.tcp = nil
      local tcp2 = self.tcp2
      if tcp2 then
        self.tcp2 = nil
        self.selector:close(tcp, function(err)
          if err then
            self.selector:close(tcp2)
            if cb then
              cb(err)
            end
          else
            self.selector:close(tcp2, cb)
          end
        end)
      else
        self.selector:close(tcp, cb)
      end
    elseif cb then
      cb()
    end
    return d
  end

  function tcpSocket:connect(addr, port, callback)
    logger:finer('connect(%s, %s)', addr, port)
    local tcp, err = luaSocketLib.connect(addr or '127.0.0.1', port)
    self.tcp = tcp
    if err then
      logger:finer('connect(%s, %s) error => "%s"', addr, port, err)
    end
    return Promise.applyCallback(callback, err, self), err
  end

  function tcpSocket:write(data, callback)
    logger:finer('write(%l)', data)
    local cb, d = Promise.ensureCallback(callback, true)
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

  function tcpSocket:bindThenListen(ai, port, backlog)
    logger:fine('bindThenListen(%t, %s, %s)', ai, port, backlog)
    local tcp, err, status
    if ai.family == 'inet' then
      tcp, err = luaSocketLib.tcp4()
    else
      tcp, err = luaSocketLib.tcp6()
    end
    if tcp then
      tcp:setoption('reuseaddr', true)
      status, err = tcp:bind(ai.addr, port)
      if status then
        status, err = tcp:listen(backlog)
        if status then
          tcp:settimeout(0) -- do not block
          self.selector:register(tcp, Selector.MODE_RECV, function()
            local c = tcp:accept()
            if c then
              self:handleAccept(c)
            end
          end)
        else
          tcp:close()
          tcp = nil
        end
      else
        tcp:close()
        tcp = nil
      end
    end
    return tcp, err
  end

  local isWindowsOS = string.sub(package.config, 1, 1) == '\\'

  function tcpSocket:bind(addr, port, backlog, callback)
    if type(backlog) ~= 'number' then
      backlog = 32
    end
    logger:finer('bind(%s, %s, %d)', addr, port, backlog)
    if not addr or addr == '::' or addr == '*' then
      addr = '0.0.0.0'
    end
    local infos, err = luaSocketLib.dns.getaddrinfo(addr)
    if not err then
      local ai = infos[1]
      local p = port or 0
      self.tcp, err = self:bindThenListen(ai, p, backlog)
      if not err and isWindowsOS then
        local ai2 = nil
        for _, r in ipairs(infos) do
          if r.family ~= ai.family then
            ai2 = r
            break
          end
        end
        if ai2 then
          if p == 0 then
            p = select(2, self.tcp:getsockname())
          end
          self.tcp2, err = self:bindThenListen(ai2, p, backlog)
          if err then
            logger:warn('second bindThenListen() in error, %s', err)
            self.tcp:close()
            self.tcp = nil
          end
        end
      end
    end
    return Promise.applyCallback(callback, err)
  end

  function tcpSocket:handleAccept(tcp)
    logger:finer('accepting %s', tcp)
    local client = TcpSocket:new(tcp)
    self:onAccept(client)
  end

  function tcpSocket:onAccept(client)
    logger:warn('closing on accept')
    client:close()
  end

end)
