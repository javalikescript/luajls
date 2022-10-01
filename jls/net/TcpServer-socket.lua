local luaSocketLib = require('socket')

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local Selector = require('jls.net.Selector-socket')
local TcpClient = require('jls.net.TcpClient-socket')

return require('jls.lang.class').create('jls.net.Tcp-socket', function(tcpServer, super)

  function tcpServer:bind(addr, port, backlog, callback)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('tcpServer:bind('..tostring(addr)..', '..tostring(port)..')')
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

  function tcpServer:handleAccept()
    local tcp = self:tcpAccept()
    if tcp then
      if logger:isLoggable(logger.DEBUG) then
        logger:debug('tcpServer:handleAccept() accepting '..Selector.socketToString(tcp))
      end
      local client = TcpClient:new(tcp)
      self:onAccept(client)
    else
      logger:debug('tcpServer:handleAccept() accept error')
    end
  end

  function tcpServer:tcpAccept()
    return self.tcp:accept()
  end

  function tcpServer:onAccept(client)
    client:close()
  end

  function tcpServer:close(callback)
    logger:debug('tcpServer:close()')
    super.close(self, callback)
  end

end)
