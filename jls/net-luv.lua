--[[--
Network module.

The network operations are only provided as asynchronous operations and thus
should be used together with an @{jls.lang.event|event} loop.

@module jls.net
@pragma nostrip

@usage
local net = require('jls.net')
local event = require('jls.lang.event')
local streams = require('jls.io.streams')

local client = net.TcpClient:new()
client:connect('127.0.0.1', 8080):next(function(err)
  client:readStart(streams.CallbackStreamHandler:new(function(err, data)
    if data then
      print('Received "'..tostring(data)..'"')
    end
    client:readStop()
    client:close()
  end))
end

event:loop()

]]

local luvLib = require('luv')

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local streams = require('jls.io.streams')

local isWindowsOS = false
if string.sub(package.config, 1, 1) == '\\' or string.find(package.cpath, '%.dll') then
  isWindowsOS = true
end

local socketToString = function(client)
  local t = client:getpeername()
  return tostring(t.ip)..':'..tostring(t.port)
end


-- User Datagram Protocol

--- The Tcp base class.
-- @type Tcp
local Tcp = class.create(function(tcp)

  function tcp:initialize(tcp)
    self.tcp = tcp
  end
  
  --- Returns the local name of this TCP socket.
  -- @treturn string the local name of this TCP socket.
  function tcp:getLocalName()
    --logger:finer('tcp:getLocalName()')
    return self.tcp:getsockname()
  end
  
  --- Returns the remote name of this TCP socket.
  -- @treturn string the remote name of this TCP socket.
  function tcp:getRemoteName()
    --logger:finer('tcp:getRemoteName()')
    return self.tcp:getpeername()
  end
  
  --- Tells whether or not this TCP socket is closed.
  -- @treturn boolean true if the TCP socket is closed.
  function tcp:closed()
    return not self.tcp
  end
  
  --- Closes this TCP socket.
  -- @tparam function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the socket is closed.
  function tcp:close(callback)
    logger:finer('tcp:close()')
    local cb, d = Promise.ensureCallback(callback)
    if self.tcp then
      self.tcp:close(cb)
      self.tcp = nil
    else
      cb()
    end
    return d
  end
end)

--- The TcpClient class.
-- A TCP Client allows to read and write on a stream connection.
-- @type TcpClient
local TcpClient = class.create(Tcp, function(tcpClient)

  --- Connects this client to the specified address and port number.
  -- @tparam string addr the address, the address could be an IP address or a host name.
  -- @tparam number port the port number.
  -- @tparam function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the client is connected.
  -- @usage
  --local s = TcpClient:new()
  --s:connect('127.0.0.1', 80)
  function tcpClient:connect(addr, port, callback)
    if logger:isLoggable(logger.FINER) then
      logger:finer('tcpClient:connect('..tostring(addr)..', '..tostring(port)..', ...)')
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
        logger:finer('tcpClient:connect() '..tostring(addr)..':'..tostring(port)..' => #'..tostring(#res))
        logger:dump(res, 'getaddrinfo', 5)
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
            logger:finer('tcpClient:connect() on '..tostring(ai.addr)..':'..tostring(ai.port))
            --logger:dump(ai, 'addr['..tostring(i)..']', 5)
          end
          client.tcp = luvLib.new_tcp()
          client.tcp:connect(ai.addr, ai.port, ccb)
        else
          if logger:isLoggable(logger.FINE) then
            logger:fine('tcpClient:connect() error "'..tostring(connectErr)..'"')
          end
          return cb(connectErr)
        end
      end
      ccb('No hostname resolution')
    end)
    return d
  end

  --- Writes data on this client.
  -- @tparam string data the data to write.
  -- @tparam function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the data has been written.
  -- @usage
  --local s = TcpClient:new()
  --s:connect('127.0.0.1', 80):next(function()
  --  s:write('Hello')
  --end)
  function tcpClient:write(data, callback)
    if logger:isLoggable(logger.FINER) then
      logger:finer('tcpClient:write('..tostring(string.len(data))..')')
    end
    local cb, d = Promise.ensureCallback(callback)
    if self.tcp then
      self.tcp:write(data, cb)
    else
      cb('closed')
    end
    return d
  end

  --- Starts reading data on this client.
  -- @param stream the stream reader, could be a function or a StreamHandler.
  -- @usage
  --local s = TcpClient:new()
  --s:connect('127.0.0.1', 80):next(function()
  --  s:readStart(function(err, data)
  --    print('received', err, data)
  --  end)
  --end)
  function tcpClient:readStart(stream)
    logger:finer('tcpClient:readStart()')
    local cb = streams.ensureCallback(stream)
    -- TODO Raise or return errors
    -- int 0 UV_EALREADY UV_ENOTCONN
    local err = 0
    if self.tcp then
      err = self.tcp:read_start(cb)
    else
      cb('closed')
    end
    if logger:isLoggable(logger.FINER) then
      logger:finer('tcpClient:readStart() => '..tostring(err))
    end
    return err
  end

  --- Stops reading data on this client.
  function tcpClient:readStop()
    logger:finer('tcpClient:readStop()')
    local err = 0
    if self.tcp then
      -- TODO Raise or return errors
      err = self.tcp:read_stop()
    end
    if logger:isLoggable(logger.FINER) then
      logger:finer('tcpClient:readStop() => '..tostring(err))
    end
    return err
  end

  --- Enables or disables TCP no delay.
  -- @tparam boolean on true to activate TCP no delay.
  function tcpClient:setTcpNoDelay(on)
    logger:finer('tcpClient:setTcpNoDelay('..tostring(on)..')')
    self.tcp:nodelay(on)
    return self
  end

  --- Enables or disables keep alive.
  -- @tparam boolean on true to activate keep alive.
  -- @tparam number delay the keep alive delay.
  function tcpClient:setKeepAlive(on, delay)
    logger:finer('tcpClient:setKeepAlive('..tostring(on)..', '..tostring(delay)..')')
    self.tcp:keepalive(on, delay)
    return self
  end
end)

--- The TcpServer class.
-- A TCP Server allows to listen and accept TCP connections.
-- @type TcpServer
local TcpServer = class.create(Tcp, function(tcpServer, super)

  function tcpServer:close(callback)
    if logger:isLoggable(logger.FINER) then
      logger:finer('tcpServer:close()')
    end
    if self.tcp2 then
      local cb, d = Promise.ensureCallback(callback)
      local server = self
      super.close(self, function(err)
        if err then
          server.tcp2:close()
          return cb(err)
        end
        server.tcp2:close(cb)
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
        logger:finer('tcpServer:handleAccept() accepting '..socketToString(tcp))
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
        logger:finer('tcpServer:accept() '..socketToString(tcp))
      end
      return tcp
    end
  end

  --- Binds this server to the specified address and port number.
  -- @tparam string node the address, the address could be an IP address or a host name.
  -- @tparam number port the port number.
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
    local server = self
    luvLib.getaddrinfo(node, port, {family = 'unspec', socktype = 'stream'}, function(err, res)
      if err then
        if logger:isLoggable(logger.FINE) then
          logger:fine('tcpServer:bind('..tostring(node)..', '..tostring(port)..') getaddrinfo() in error, '..tostring(err))
        end
        return cb(err)
      end
      if logger:isLoggable(logger.FINER) then
        logger:finer('tcpServer:bind() '..tostring(node)..':'..tostring(port)..' => #'..tostring(#res))
        logger:dump(res, 'getaddrinfo', 5)
      end
      local ai = res[1]
      local bindErr
      server.tcp, bindErr = server:bindThenListen(ai.addr, ai.port, backlog)
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
          server.tcp2, bindErr = server:bindThenListen(ai2.addr, ai2.port, backlog)
          if bindErr then
            if logger:isLoggable(logger.FINE) then
              logger:warn('tcpServer:bind() second bindThenListen() in error, '..tostring(bindErr))
            end
            server.tcp:close()
            server.tcp = nil
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

local function getAddressInfo(node, port, callback)
  local cb, d = Promise.ensureCallback(callback)
  luvLib.getaddrinfo(node, port, {family = 'unspec', socktype = 'stream'}, cb)
  return d
end

local function getNameInfo(addr, callback)
  local cb, d = Promise.ensureCallback(callback)
  luvLib.getnameinfo({ip = addr}, cb)
  return d
end


-- User Datagram Protocol

--- The UdpSocket class.
-- An UDP socker allows to send and receive datagram packets.
-- @type UdpSocket
local UdpSocket = class.create(function(udpSocket)

  function udpSocket:initialize(nds)
    self.nds = nds or luvLib.new_udp()
  end

  --- Binds this socket to the specified address and port number.
  -- @tparam string addr the IP address.
  -- @tparam number port the port number.
  -- @tparam table options the options to set, available options are reuseaddr and ipv6only.
  -- @usage
  --local s = UdpSocket:new()
  --s:bind('0.0.0.0', 1900, {reuseaddr = true, ipv6only = false})
  function udpSocket:bind(addr, port, options)
    if logger:isLoggable(logger.FINER) then
      logger:finer('udpSocket:bind('..tostring(addr)..', '..tostring(port)..')')
    end
    return self.nds:bind(addr, port, options)
  end

  function udpSocket:getLocalName()
    local sn = luvLib.udp_getsockname(self.nds)
    return sn.ip, sn.port, sn.family
  end

  function udpSocket:getPort()
    local sn = luvLib.udp_getsockname(self.nds)
    return sn.port, sn.ip, sn.family
  end

  --- Enables or disables broadcast.
  -- @tparam boolean value true to activate broadcast.
  function udpSocket:setBroadcast(value)
    if logger:isLoggable(logger.FINER) then
      logger:finer('udpSocket:setBroadcast('..tostring(value)..')')
    end
    return self.nds:set_broadcast(value)
  end

  --- Enables or disables multicast loopback mode.
  -- @tparam boolean value true to activate loopback mode.
  function udpSocket:setLoopbackMode(value)
    if logger:isLoggable(logger.FINER) then
      logger:finer('udpSocket:setLoopbackMode('..tostring(value)..')')
    end
    return self.nds:set_multicast_loop(value)
  end

  --- Sets the multicast time to live value.
  -- @tparam number value the time to live.
  function udpSocket:setTimeToLive(value)
    if logger:isLoggable(logger.FINER) then
      logger:finer('udpSocket:setTimeToLive('..tostring(value)..')')
    end
    return self.nds:set_multicast_ttl(value)
  end

  --- Sets the multicast interface.
  -- @tparam string ifaddr the multicast interface.
  function udpSocket:setInterface(ifaddr)
    if logger:isLoggable(logger.FINER) then
      logger:finer('udpSocket:setInterface('..tostring(ifaddr)..')')
    end
    return self.nds:set_multicast_interface(ifaddr)
  end

  --- Joins a group.
  -- @tparam string mcastaddr the multicast address.
  -- @tparam string ifaddr the interface address.
  function udpSocket:joinGroup(mcastaddr, ifaddr)
    if logger:isLoggable(logger.FINER) then
      logger:finer('udpSocket:joinGroup('..tostring(mcastaddr)..', '..tostring(ifaddr)..')')
    end
    return self.nds:set_membership(mcastaddr, ifaddr, 'join')
  end

  --- Leaves a group.
  -- @tparam string mcastaddr the multicast address.
  -- @tparam string ifaddr the interface address.
  function udpSocket:leaveGroup(mcastaddr, ifaddr)
    if logger:isLoggable(logger.FINER) then
      logger:finer('udpSocket:leaveGroup('..tostring(mcastaddr)..', '..tostring(ifaddr)..')')
    end
    return self.nds:set_membership(mcastaddr, ifaddr, 'leave')
  end

  --- Starts receiving datagram packets on this socket.
  -- @param stream the stream reader, could be a function or a StreamHandler.
  -- @usage
  --local s = UdpSocket:new()
  --s:receiveStart(function(err, data)
  --  print('received', err, data)
  --end)
  function udpSocket:receiveStart(stream)
    logger:finer('udpSocket:receiveStart(?)')
    local cb = streams.ensureCallback(stream)
    -- TODO Raise or return errors
    -- int 0 UV_EALREADY UV_ENOTCONN
    local err = 0
    if self.nds then
      err = self.nds:recv_start(cb)
    else
      cb('closed')
    end
    if logger:isLoggable(logger.FINER) then
      logger:finer('udpSocket:receiveStart() => '..tostring(err))
    end
    return err
  end

  --- Stops receiving datagram packets on this socket.
  function udpSocket:receiveStop()
    logger:finer('udpSocket:receiveStop()')
    local err = 0
    if self.nds then
      -- TODO Raise or return errors
      err = self.nds:recv_stop()
    end
    if logger:isLoggable(logger.FINER) then
      logger:finer('udpSocket:receiveStop() => '..tostring(err))
    end
    return err
  end

  --- Sends the specified datagram packet on this socket to the specified address and port number.
  -- @tparam string data the datagram packet as a string.
  -- @tparam string addr the IP address.
  -- @tparam number port the port number.
  -- @tparam function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the data has been sent.
  -- @usage
  --local s = UdpSocket:new()
  --s:send('Hello', '239.255.255.250', 1900)
  function udpSocket:send(data, addr, port, callback)
    if logger:isLoggable(logger.FINER) then
      logger:finer('udpSocket:send('..tostring(string.len(data))..')')
    end
    local cb, d = Promise.ensureCallback(callback)
    if self.nds then
      self.nds:send(data, addr, port, cb)
    else
      cb('closed')
    end
    return d
  end

  --- Closes this socket.
  -- @tparam function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once this socket is closed.
  function udpSocket:close(callback)
    logger:finer('udpSocket:close()')
    local cb, d = Promise.ensureCallback(callback)
    if self.nds then
      self.nds:close(cb)
      self.nds = nil
    else
      cb()
    end
    return d
  end
end)

return {
  anyIPv4 = '0.0.0.0',
  anyIPv6 = '::',
  socketToString = socketToString,
  getAddressInfo = getAddressInfo,
  getNameInfo = getNameInfo,
  TcpServer = TcpServer,
  TcpClient = TcpClient,
  UdpSocket = UdpSocket
}