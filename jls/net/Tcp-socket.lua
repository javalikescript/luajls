local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local Selector = require('jls.net.Selector-socket')

return require('jls.lang.class').create(function(tcp)
  function tcp:initialize(tcp, selector)
    self.tcp = tcp
    self.selector = selector or Selector.DEFAULT
  end

  function tcp:getLocalName()
    --logger:debug('tcp:getLocalName()')
    return self.tcp:getsockname()
  end

  function tcp:getRemoteName()
    --logger:debug('tcp:getRemoteName()')
    return self.tcp:getPeerName()
  end

  function tcp:isClosed()
    return not self.tcp
  end

  function tcp:close(callback)
    logger:debug('tcp:close()')
    local cb, d = Promise.ensureCallback(callback)
    local socket = self.tcp
    if socket then
      self.tcp = nil
      self.selector:close(socket, cb)
    else
      cb()
    end
    return d
  end

end)
