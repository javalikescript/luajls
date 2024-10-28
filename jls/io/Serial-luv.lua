local luvLib = require('luv')
local logger = require('jls.lang.logger'):get(...)
local StreamHandler = require('jls.io.StreamHandler')

return require('jls.lang.class').create('jls.io.SerialBase', function(serial)

  function serial:readStart(stream)
    logger:finer('readStart()')
    if self.waitThread then
      error('read already started')
    end
    self.streamCallback = StreamHandler.ensureCallback(stream)
    local errAsync = luvLib.new_async(function(err)
      if err == 'close' then
        self.streamCallback()
      else
        logger:fine('Error while waiting serial data %s', err)
        self.streamCallback(err or 'unknown error')
      end
    end)
    local waitAsync = luvLib.new_async(function()
      self:readAvailable(self.streamCallback)
    end)
    self.waitThread = luvLib.new_thread(function(fd, async, asyncErr, path, cpath)
      package.path = path
      package.cpath = cpath
      local serialLib = require('serial')
      local luv = require('luv')
      while true do
        local status, err = serialLib.waitDataAvailable(fd, 5000) -- will block
        if not status then
          if err ~= 'timeout' then
            asyncErr:send(err or 'unknown error')
            break
          end
        else
          async:send()
          luv.sleep(1) -- let async event be handled
        end
      end
      async:close()
      asyncErr:close()
    end, self.fileDesc.fd, waitAsync, errAsync, package.path, package.cpath)
  end

  function serial:readStop()
    logger:finer('readStop()')
    if self.waitThread then
      self.waitThread:join()
      self.waitThread = nil
      self.streamCallback = nil
    end
  end

end)
