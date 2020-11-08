--- This class enables to manage TCP socket.
-- @module jls.net.Tcp

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')

--- The Tcp base class.
-- @type Tcp
return require('jls.lang.class').create(function(tcp)

  function tcp:initialize(tcp)
    self.tcp = tcp
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
