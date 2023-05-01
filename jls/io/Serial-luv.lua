local luvLib = require('luv')
local logger = require('jls.lang.logger')
local StreamHandler = require('jls.io.StreamHandler')

return require('jls.lang.class').create('jls.io.SerialBase', function(serial)

  function serial:readStart(stream)
    logger:finer('serial:readStart()')
    self.streamCallback = StreamHandler.ensureCallback(stream)
    local waitAsync = luvLib.new_async(function(err)
      if err then
        if err == 'close' then
          self.streamCallback()
        else
          logger:fine('Error while waiting serial data '..tostring(err))
          self.streamCallback(err)
        end
      else
        self:readAvailable(self.streamCallback)
      end
    end)
    self.waitThread = luvLib.new_thread(function(fd, async, path, cpath)
      package.path = path
      package.cpath = cpath
      local serialLib = require('serial')
      while true do
        local status, err = serialLib.waitDataAvailable(fd, 5000) -- will block
        if not status then
          if err ~= 'timeout' then
            async:send(err or 'unknown error')
            break
          end
        else
          async:send()
        end
      end
      async:close()
    end, self.fileDesc.fd, waitAsync, package.path, package.cpath)
  end

  function serial:readStop()
    logger:finer('serial:readStop()')
    if self.waitThread then
      self.waitThread:join()
      self.waitThread = nil
      self.streamCallback = nil
    end
  end

end)
