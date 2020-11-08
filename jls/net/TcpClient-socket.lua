local luaSocketLib = require('socket')

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local StreamHandler = require('jls.io.streams.StreamHandler')
local Selector = require('jls.net.Selector-socket')

return require('jls.lang.class').create('jls.net.Tcp-socket', function(tcpClient)

  function tcpClient:connect(addr, port, callback)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('tcpClient:connect('..tostring(addr)..', '..tostring(port)..')')
    end
    local tcp, err = luaSocketLib.connect(addr or '127.0.0.1', port)
    self.tcp = tcp
    local cb, d = Promise.ensureCallback(callback)
    if err then
      if logger:isLoggable(logger.DEBUG) then
        logger:debug('tcpClient:connect('..tostring(addr)..', '..tostring(port)..') error => "'..tostring(err)..'"')
      end
      cb(err)
    else
      cb(nil, self)
    end
    return d
  end

  function tcpClient:write(data, callback)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('tcpClient:write('..tostring(string.len(data))..')')
    end
    local cb, d = Promise.ensureCallback(callback)
    if self.tcp then
      self.selector:register(self.tcp, nil, nil, data, cb)
    else
      cb('closed')
    end
    return d
  end

  function tcpClient:readStart(cb)
    logger:debug('tcpClient:readStart(?)')
    local stream = StreamHandler.ensureStreamHandler(cb)
    if self.tcp then
      self.selector:register(self.tcp, nil, stream)
    else
      stream:onError('closed')
    end
    return self
  end

  function tcpClient:readStop()
    logger:debug('tcpClient:readStop()')
    if self.tcp then
      self.selector:unregister(self.tcp, Selector.MODE_RECV)
    end
    return self
  end

  function tcpClient:setTcpNoDelay(on)
    logger:debug('tcpClient:setTcpNoDelay('..tostring(on)..')')
    return self.tcp:setoption('tcp-nodelay', on)
  end

  function tcpClient:setKeepAlive(on, delay)
    logger:debug('tcpClient:setKeepAlive('..tostring(on)..', '..tostring(delay)..')')
    return self.tcp:setoption('keepalive', on)
  end

end, function(TcpClient)

  TcpClient.socketToString = Selector.socketToString

end)
