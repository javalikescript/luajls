--- Represents a UDP socket.
-- @module jls.net.UdpSocket

local luvLib = require('luv')

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local StreamHandler = require('jls.io.StreamHandler')

-- User Datagram Protocol

--- The UdpSocket class.
-- An UDP socker allows to send and receive datagram packets.
-- @type UdpSocket
return require('jls.lang.class').create(function(udpSocket)

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
  --s:receiveStart(function(err, data, addr)
  --  print('received', err, data)
  --end)
  function udpSocket:receiveStart(stream)
    logger:finer('udpSocket:receiveStart(?)')
    local cb = StreamHandler.ensureCallback(stream)
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
