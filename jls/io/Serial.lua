-- Provide serial input/output communication.
-- @module jls.io.Serial
-- @pragma nostrip

local logger = require('jls.lang.logger')

local serialLib = require('serial')
local luvLib = require('luv')

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
    logger:debug('serial:readStart()')
    self.stream = stream;
    local fileDesc = self.fileDesc
    local waitAsync = luvLib.new_async(function(err)
      while true do
        local count = serialLib.available(fileDesc.fd)
        if not count or count <= 0 then
          break
        end
        local data = fileDesc:readSync(count)
        stream:onData(data)
        --stream:onError(err)
      end
    end)
    local waitThread = luvLib.new_thread(function(fd, async)
      local serialLib = require('serial')
      while true do
        local status, err = serialLib.waitDataAvailable(fd, 5000) -- will block
        if not status then
          -- TODO handle close
          if err ~= 'timeout' then
            if err ~= 'close' then
              print('Error while waiting serial data '..tostring(err))
            end
            break
          end
        else
          async:send()
        end
      end
      async:close()
    end, fileDesc.fd, waitAsync)
  end

  function serial:readStop()
    logger:debug('serial:readStop()')
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

