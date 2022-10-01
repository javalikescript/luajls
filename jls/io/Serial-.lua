local serialLib = require('serial')
local loader = require('jls.lang.loader')
local logger = require('jls.lang.logger')
local event = loader.requireOne('jls.lang.event-')
local StreamHandler = require('jls.io.StreamHandler')

return require('jls.lang.class').create('jls.io.SerialBase', function(serial, super)

  function serial:initialize(...)
    super.initialize(self, ...)
  end

  function serial:readStart(stream)
    logger:finer('serial:readStart()')
    local cb = StreamHandler.ensureCallback(stream)
    self.readTaskId = event:setTask(function(timeoutMs)
      local status, err = serialLib.waitDataAvailable(self.fileDesc.fd, timeoutMs)
      if status then
        serial:readAvailable(cb)
        return true
      end
      if err == 'timeout' then
        return true
      end
      if err == 'close' then
        cb()
      else
        logger:fine('Error while waiting serial data '..tostring(err))
        cb(err or 'Error while waiting serial data')
      end
      self.readTaskId = nil
      return false
    end, -1)
  end

  function serial:readStop()
    logger:finer('serial:readStop()')
    if self.readTaskId then
      event:clearInterval(self.readTaskId)
      self.readTaskId = nil
    end
  end

end)
