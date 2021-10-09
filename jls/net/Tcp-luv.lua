--- TCP socket base class.
-- @module jls.net.Tcp

local close = require('jls.lang.luv_stream').close

--- The Tcp base class.
-- @type Tcp
return require('jls.lang.class').create(function(tcp)

  function tcp:initialize(stream)
    self.tcp = stream
  end

  --- Returns the local name of this TCP socket.
  -- @treturn string the local name of this TCP socket.
  function tcp:getLocalName()
    --logger:finer('tcp:getLocalName()')
    local addr = self.tcp:getsockname()
    if addr then
      return addr.ip, addr.port, addr.family
    end
    return nil
  end

  --- Returns the remote name of this TCP socket.
  -- @treturn string the remote name of this TCP socket.
  function tcp:getRemoteName()
    --logger:finer('tcp:getRemoteName()')
    local addr = self.tcp:getpeername()
    if addr then
      return addr.ip, addr.port, addr.family
    end
    return nil
  end

  --- Tells whether or not this TCP socket is closed.
  -- @treturn boolean true if the TCP socket is closed.
  function tcp:isClosed()
    return not self.tcp
  end

  --- Closes this TCP socket.
  -- @tparam function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the socket is closed.
  function tcp:close(callback)
    local stream = self.tcp
    self.tcp = nil
    return close(stream, callback)
  end

end)
