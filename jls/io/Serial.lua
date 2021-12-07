--[[
Provide serial input/output communication.

Note: The only implementation is based on libuv

TODO Switch to a channel based implementation to avoid the libuv restriction

@module jls.io.Serial
@pragma nostrip
]]

local serialLib = require('serial')
local luvLib = require('luv')

local logger = require('jls.lang.logger')
local StreamHandler = require('jls.io.streams.StreamHandler')

-- A Serial class.
-- A Serial instance represents a serial device.
-- @type Serial
return require('jls.lang.class').create(function(serial)
  -- Creates a new Serial object based on the specified file desciptor.
  -- @function serial:new
  function serial:initialize(fileDesc)
    self.fileDesc = fileDesc
  end

  function serial:getFileDescriptor()
    return self.fileDesc
  end

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
        while true do
          local count = serialLib.available(self.fileDesc.fd)
          if not count or count <= 0 then
            break
          end
          local data = self.fileDesc:readSync(count) -- should not block
          self.streamCallback(nil, data)
        end
      end
    end)
    self.waitThread = luvLib.new_thread(function(fd, async)
      local serialLib = require('serial')
      while true do
        local status, err = serialLib.waitDataAvailable(fd, 5000) -- will block
        if not status then
          if err ~= 'timeout' then
            async:send(err)
            break
          end
        else
          async:send()
        end
      end
      async:close()
    end, self.fileDesc.fd, waitAsync)
  end

  function serial:readStop()
    logger:finer('serial:readStop()')
    if self.waitThread then
      self.waitThread:join()
      self.waitThread = nil
      self.streamCallback = nil
    end
  end

  function serial:write(data)
    return self.fileDesc:writeSync(data)
  end

  function serial:close()
    return self.fileDesc:closeSync()
  end

  function serial:flush()
    return serialLib.flush(self.fileDesc.fd)
  end

end, function(Serial)

  local FileDescriptor = require('jls.io.FileDescriptor')

  function Serial.open(name, options)
    if type(options) ~= 'table' then
      options = {}
    end
    -- we may try using mode O_RDWR | O_NOCTTY | O_NDELAY
    local fileDesc, err = FileDescriptor.openSync(name, options.mode or 'r+')
    if not fileDesc then
      return nil, err
    end
    if type(options.flush) == 'nil' or options.flush then
      logger:debug('Serial:open() flushing')
      serialLib.flush(fileDesc.fd)
    end
    serialLib.setSerial(fileDesc.fd, options.baudRate, options.dataBits, options.stopBits, options.parity)
    --serialLib.setTimeOut(fileDesc.fd, 5000, 5000)
    return Serial:new(fileDesc)
  end
end)

