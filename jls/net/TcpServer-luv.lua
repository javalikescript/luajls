--- Provides TCP server socket class.
-- @module jls.net.TcpServer

local luvLib = require('luv')

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local TcpClient = require('jls.net.TcpClient-luv')

local isWindowsOS = false
if string.sub(package.config, 1, 1) == '\\' or string.find(package.cpath, '%.dll') then
  isWindowsOS = true
end

--- The TcpServer class.
-- A TCP Server allows to listen and accept TCP connections.
-- @type TcpServer
return require('jls.lang.class').create('jls.net.Tcp-luv', function(tcpServer, super)

    function tcpServer:close(callback)
    if logger:isLoggable(logger.FINER) then
      logger:finer('tcpServer:close()')
    end
    if self.tcp2 then
      local cb, d = Promise.ensureCallback(callback)
      local server = self
      super.close(self, function(err)
        if err then
          server.tcp2:close(false)
          if cb then
            cb(err)
          end
        else
          server.tcp2:close(cb)
        end
      end)
      return d
    end
    return super.close(self, callback)
  end

  function tcpServer:bindThenListen(addr, port, backlog)
    backlog = backlog or 32
    if logger:isLoggable(logger.FINER) then
      logger:finer('tcpServer:bindThenListen('..tostring(addr)..', '..tostring(port)..', '..tostring(backlog)..')')
    end
    local server = self
    local tcp = luvLib.new_tcp()
    -- to disable dual-stack support and use only IPv6: {ipv6only = true}
    local _, err = tcp:bind(addr, port)
    if err then
      tcp:close()
      return nil, err
    end
    _, err = tcp:listen(backlog, function(err)
      assert(not err, err) -- TODO Handle errors
      server:handleAccept()
    end)
    if err then
      tcp:close()
      return nil, err
    end
    return tcp
  end

  function tcpServer:handleAccept()
    local tcp = self:tcpAccept()
    if tcp then
      if logger:isLoggable(logger.FINER) then
        logger:finer('tcpServer:handleAccept() accepting '..TcpClient.socketToString(tcp))
      end
      local client = TcpClient:new(tcp)
      self:onAccept(client)
    else
      logger:finer('tcpServer:handleAccept() accept error')
    end
  end

  function tcpServer:tcpAccept()
    if self.tcp then
      local tcp = luvLib.new_tcp()
      self.tcp:accept(tcp)
      if logger:isLoggable(logger.FINER) then
        logger:finer('tcpServer:accept() '..TcpClient.socketToString(tcp))
      end
      return tcp
    end
  end

  --- Binds this server to the specified address and port number.
  -- @tparam string node the address, the address could be an IP address or a host name.
  -- @tparam number port the port number, 0 to let the system automatically choose a port.
  -- @tparam[opt] number backlog the accept queue size, default is 32.
  -- @tparam[opt] function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the server is bound.
  -- @usage
  --local s = TcpServer:new()
  --s:bind('127.0.0.1', 80)
  function tcpServer:bind(node, port, backlog, callback)
    if type(backlog) ~= 'number' then
      backlog = 32
    end
    if logger:isLoggable(logger.FINER) then
      logger:finer('tcpServer:bind('..tostring(node)..', '..tostring(port)..')')
    end
    local cb, d = Promise.ensureCallback(callback)
    -- FIXME getaddrinfo does not have a port argument
    luvLib.getaddrinfo(node, port, {family = 'unspec', socktype = 'stream'}, function(err, res)
      if err then
        if logger:isLoggable(logger.FINE) then
          logger:fine('tcpServer:bind('..tostring(node)..', '..tostring(port)..') getaddrinfo() in error, '..tostring(err))
        end
        return cb(err)
      end
      if logger:isLoggable(logger.FINER) then
        logger:finer('tcpServer:bind() '..tostring(node)..':'..tostring(port)..' => #'..tostring(#res))
        --logger:finer('getaddrinfo '..require('jls.util.tables').stringify(res, 2))
      end
      local ai = res[1]
      local bindErr
      self.tcp, bindErr = self:bindThenListen(ai.addr, ai.port or port, backlog)
      if bindErr then
        if logger:isLoggable(logger.FINE) then
          logger:fine('tcpServer:bind() bindThenListen() in error, '..tostring(bindErr))
        end
        return cb(bindErr)
      end
      -- TODO check if dual socket is necessary on other OSes
      -- see https://stackoverflow.com/questions/37729475/create-dual-stack-socket-on-all-loopback-interfaces-on-windows
      if isWindowsOS then
        local ai2 = nil
        for _, r in ipairs(res) do
          if r.family ~= ai.family then
            ai2 = r
            break
          end
        end
        if ai2 then
          self.tcp2, bindErr = self:bindThenListen(ai2.addr, ai2.port or port, backlog)
          if bindErr then
            if logger:isLoggable(logger.FINE) then
              logger:warn('tcpServer:bind() second bindThenListen() in error, '..tostring(bindErr))
            end
            self.tcp:close()
            self.tcp = nil
            return cb(bindErr)
          end
        end
      end
      --logger:finer('tcpServer:bind() completed')
      return cb()
    end)
    return d
  end

  --- Accepts a new TCP client.
  -- This method should be overriden, the default implementation closes the client.
  -- @param client the TCP client to accept.
  -- @usage
  --local s = TcpServer:new()
  --function s:onAccept(client)
  --  client:close()
  --end
  function tcpServer:onAccept(client)
    client:close()
  end

end)
