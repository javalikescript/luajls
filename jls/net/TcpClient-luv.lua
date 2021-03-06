--[[--
Provide TCP client socket class.

The network operations are only provided as asynchronous operations and thus
should be used together with an @{jls.lang.event|event} loop.

@module jls.net.TcpClient

@usage
local TcpClient = require('jls.net.TcpClient')
local event = require('jls.lang.event')

local client = TcpClient:new()
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

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local StreamHandler = require('jls.io.streams.StreamHandler')

local isWindowsOS = false
if string.sub(package.config, 1, 1) == '\\' or string.find(package.cpath, '%.dll') then
  isWindowsOS = true
end

if not isWindowsOS and not os.getenv('JLS_DO_NOT_IGNORE_SIGPIPE') then
  -- lua socket core installs a handler to ignore sigpipe in order to avoid crash
  -- signal(SIGPIPE, SIG_IGN);
  if pcall(require, 'socket.core') then
    if logger:isLoggable(logger.FINE) then
      logger:fine('TcpClient-luv: ignoring SIGPIPE, use environment "JLS_DO_NOT_IGNORE_SIGPIPE" to disable')
    end
  end
end

local function socketToString(client)
  local t = client:getpeername()
  return tostring(t.ip)..':'..tostring(t.port)
end

--- The TcpClient class.
-- A TCP Client allows to read and write on a stream connection.
-- @type TcpClient
return require('jls.lang.class').create('jls.net.Tcp-luv', function(tcpClient)

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
    local cb = StreamHandler.ensureCallback(stream)
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

end, function(TcpClient)

  TcpClient.socketToString = socketToString

end)
