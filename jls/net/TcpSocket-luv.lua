--[[--
Represents a TCP socket.

The network operations are only provided as asynchronous operations and thus
should be used together with an @{jls.lang.event|event} loop.

@module jls.net.TcpSocket
@pragma nostrip

@usage
local TcpSocket = require('jls.net.TcpSocket')
local event = require('jls.lang.event')

local client = TcpSocket:new()
client:connect('127.0.0.1', 8080):next(function(err)
  client:readStart(function(err, data)
    if data then
      print('Received "'..tostring(data)..'"')
    end
    client:readStop()
    client:close()
  end)
end

event:loop()

]]

local luvLib = require('luv')
local luv_stream = require('jls.lang.luv_stream')
local close, read_start, read_stop, write = luv_stream.close, luv_stream.read_start, luv_stream.read_stop, luv_stream.write

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')

local isWindowsOS = string.sub(package.config, 1, 1) == '\\'

--[[
  When a process writes to a socket that has received an RST, the SIGPIPE signal is sent to the process.
  The default action of this signal is to terminate the process, so the process must catch the signal to avoid being involuntarily terminated.
]]
if not isWindowsOS and not os.getenv('JLS_DO_NOT_IGNORE_SIGPIPE') then
  if logger:isLoggable(logger.FINE) then
    logger:fine('TcpSocket-luv: ignoring SIGPIPE, use environment "JLS_DO_NOT_IGNORE_SIGPIPE" to disable')
  end
  local state, linuxLib = pcall(require, 'linux')
  if state then
    linuxLib.signal(linuxLib.constants.SIGPIPE, 'SIG_IGN')
  else
    pcall(require, 'socket.core')
  end
end

local function socketToString(client)
  if client then
    local t = client:getpeername()
    if t then
      return tostring(t.ip)..':'..tostring(t.port)
    end
  end
  return 'n/a'
end

--- The TcpSocket class.
-- A TCP Client allows to read and write on a TCP connection.
-- A TCP Server allows to listen and accept TCP connections.
-- @type TcpSocket
return require('jls.lang.class').create(function(tcpSocket, _, TcpSocket)

  function tcpSocket:initialize(tcp)
    self.tcp = tcp
  end

  --- Returns the local name of this TCP socket.
  -- @treturn string the local name of this TCP socket.
  function tcpSocket:getLocalName()
    --logger:finer('tcp:getLocalName()')
    local addr = self.tcp:getsockname()
    if addr then
      return addr.ip, addr.port, addr.family
    end
    return nil
  end

  --- Returns the remote name of this TCP socket.
  -- @treturn string the remote name of this TCP socket.
  function tcpSocket:getRemoteName()
    --logger:finer('tcp:getRemoteName()')
    local addr = self.tcp:getpeername()
    if addr then
      return addr.ip, addr.port, addr.family
    end
    return nil
  end

  --- Tells whether or not this TCP socket is closed.
  -- @treturn boolean true if the TCP socket is closed.
  function tcpSocket:isClosed()
    return not self.tcp
  end

  --- Closes this TCP socket.
  -- @tparam[opt] function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the socket is closed.
  function tcpSocket:close(callback)
    if logger:isLoggable(logger.FINER) then
      logger:finer('tcpSocket:close()')
    end
    local tcp = self.tcp
    self.tcp = nil
    if self.tcp2 then
      local tcp2 = self.tcp2
      self.tcp2 = nil
      local cb, d = Promise.ensureCallback(callback)
      close(tcp, function(err)
        if err then
          tcp2:close(false)
          if cb then
            cb(err)
          end
        else
          tcp2:close(cb)
        end
      end)
      return d
    end
    return close(tcp, callback)
  end

  --- Connects this client to the specified address and port number.
  -- @tparam string addr the address, the address could be an IP address or a host name.
  -- @tparam number port the port number.
  -- @tparam[opt] function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the client is connected.
  -- @usage
  --local s = TcpSocket:new()
  --s:connect('127.0.0.1', 80)
  function tcpSocket:connect(addr, port, callback)
    if logger:isLoggable(logger.FINER) then
      logger:finer('tcpSocket:connect('..tostring(addr)..', '..tostring(port)..', ...)')
    end
    local client = self
    local cb, d = Promise.ensureCallback(callback)
    -- family and protocol: inet inet6 unix ipx netlink x25 ax25 atmpvc appletalk packet
    -- socktype: stream dgram seqpacket raw rdm
    luvLib.getaddrinfo(addr, port, {family = 'unspec', socktype = 'stream'}, function(err, res)
      if err then
        return cb(err)
      end
      if logger:isLoggable(logger.FINER) then
        logger:finer('tcpSocket:connect() '..tostring(addr)..':'..tostring(port)..' => #'..tostring(#res))
        --logger:finer('getaddrinfo: '..require('jls.util.tables').stringify(res, 2))
      end
      local ccb, i = nil, 0
      -- try to connect to each translated/resolved address using the first succesful one
      ccb = function(connectErr)
        if not connectErr then
          return cb(nil, client)
        end
        if client.tcp then
          client.tcp:close()
          client.tcp = nil
        end
        if i < #res then
          i = i + 1
          local ai = res[i]
          if logger:isLoggable(logger.FINER) then
            logger:finer('tcpSocket:connect() on '..tostring(ai.addr)..':'..tostring(ai.port))
            --logger:finer('addr['..tostring(i)..'] '..require('jls.util.tables').stringify(ai, 2))
          end
          client.tcp = luvLib.new_tcp()
          client.tcp:connect(ai.addr, ai.port, ccb)
        else
          if logger:isLoggable(logger.FINE) then
            logger:fine('tcpSocket:connect() error "'..tostring(connectErr)..'"')
          end
          return cb(connectErr)
        end
      end
      ccb('No hostname resolution')
    end)
    return d
  end

  --- Writes data on this client.
  -- @tparam string data the data to write, could be a table of string.
  -- @tparam[opt] function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the data has been written.
  -- @usage
  --local s = TcpSocket:new()
  --s:connect('127.0.0.1', 80):next(function()
  --  s:write('Hello')
  --end)
  function tcpSocket:write(data, callback)
    return write(self.tcp, data, callback)
  end

  --- Starts reading data on this client.
  -- @param sh the stream handler, could be a function or a StreamHandler.
  -- @usage
  --local s = TcpSocket:new()
  --s:connect('127.0.0.1', 80):next(function()
  --  s:readStart(function(err, data)
  --    print('received', err, data)
  --  end)
  --end)
  function tcpSocket:readStart(sh)
    return read_start(self.tcp, sh)
  end

  --- Stops reading data on this client.
  function tcpSocket:readStop()
    return read_stop(self.tcp)
  end

  --- Enables or disables TCP no delay.
  -- @tparam boolean on true to activate TCP no delay.
  function tcpSocket:setTcpNoDelay(on)
    logger:finer('tcpSocket:setTcpNoDelay('..tostring(on)..')')
    self.tcp:nodelay(on)
    return self
  end

  --- Enables or disables keep alive.
  -- @tparam boolean on true to activate keep alive.
  -- @tparam number delay the keep alive delay.
  function tcpSocket:setKeepAlive(on, delay)
    logger:finer('tcpSocket:setKeepAlive('..tostring(on)..', '..tostring(delay)..')')
    self.tcp:keepalive(on, delay)
    return self
  end

  function tcpSocket:bindThenListen(addr, port, backlog)
    backlog = backlog or 32
    if logger:isLoggable(logger.FINER) then
      logger:finer('tcpSocket:bindThenListen('..tostring(addr)..', '..tostring(port)..', '..tostring(backlog)..')')
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

  function tcpSocket:handleAccept()
    local tcp = self:tcpAccept()
    if tcp then
      if logger:isLoggable(logger.FINER) then
        logger:finer('tcpSocket:handleAccept() accepting '..socketToString(tcp))
      end
      local client = TcpSocket:new(tcp)
      self:onAccept(client)
    else
      logger:finer('tcpSocket:handleAccept() accept error')
    end
  end

  function tcpSocket:tcpAccept()
    if self.tcp then
      local tcp = luvLib.new_tcp()
      self.tcp:accept(tcp)
      if logger:isLoggable(logger.FINER) then
        logger:finer('tcpSocket:accept() '..socketToString(tcp))
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
  --local s = TcpSocket:new()
  --s:bind('127.0.0.1', 80)
  function tcpSocket:bind(node, port, backlog, callback)
    if type(backlog) ~= 'number' then
      backlog = 32
    end
    if logger:isLoggable(logger.FINER) then
      logger:finer('tcpSocket:bind('..tostring(node)..', '..tostring(port)..')')
    end
    local cb, d = Promise.ensureCallback(callback)
    -- FIXME getaddrinfo does not have a port argument
    luvLib.getaddrinfo(node, port, {family = 'unspec', socktype = 'stream'}, function(err, res)
      if err then
        if logger:isLoggable(logger.FINE) then
          logger:fine('tcpSocket:bind('..tostring(node)..', '..tostring(port)..') getaddrinfo() in error, '..tostring(err))
        end
        return cb(err)
      end
      if logger:isLoggable(logger.FINER) then
        logger:finer('tcpSocket:bind() '..tostring(node)..':'..tostring(port)..' => #'..tostring(#res))
      end
      --logger:info('getaddrinfo(%s, %s) %s', node, port, require('jls.util.tables').stringify(res, 2))
      local ai = res[1]
      local bindErr
      local p = port or ai.port or 0
      self.tcp, bindErr = self:bindThenListen(ai.addr, p, backlog)
      if bindErr then
        if logger:isLoggable(logger.FINE) then
          logger:fine('tcpSocket:bind() bindThenListen() in error, '..tostring(bindErr))
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
          if p == 0 then
            local addr = self.tcp:getsockname()
            if addr and addr.port then
              p = addr.port
            end
          end
          self.tcp2, bindErr = self:bindThenListen(ai2.addr, p, backlog)
          if bindErr then
            if logger:isLoggable(logger.FINE) then
              logger:warn('tcpSocket:bind() second bindThenListen() in error, '..tostring(bindErr))
            end
            self.tcp:close()
            self.tcp = nil
            return cb(bindErr)
          end
        end
      end
      --logger:finer('tcpSocket:bind() completed')
      return cb()
    end)
    return d
  end

  --- Accepts a new TCP client.
  -- This method should be overriden, the default implementation closes the client.
  -- @param client the TCP client to accept.
  -- @usage
  --local s = TcpSocket:new()
  --function s:onAccept(client)
  --  client:close()
  --end
  function tcpSocket:onAccept(client)
    client:close()
  end

  TcpSocket.socketToString = socketToString

end)
