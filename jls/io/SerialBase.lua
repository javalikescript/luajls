--[[--
Provides serial input/output communication.

@module jls.io.Serial
@pragma nostrip
]]

local serialLib = require('serial')

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')

--- A Serial class.
-- A Serial instance represents a serial device.
-- @type Serial
return class.create(function(serial)

  -- Creates a new Serial object based on the specified file desciptor.
  -- @function serial:new
  function serial:initialize(fileDesc)
    self.fileDesc = fileDesc
  end

  function serial:getFileDescriptor()
    return self.fileDesc
  end

  --- Starts reading data on this serial device.
  -- @param stream the stream reader, could be a function or a @{jls.io.StreamHandler}.
  -- @function serial:readStart
  serial.readStart = class.notImplementedFunction

  --- Stops reading data on this serial device.
  -- @function serial:readStop
  serial.readStop = class.notImplementedFunction

  function serial:readAvailable(callback)
    local done = false
    while true do
      local count = serialLib.available(self.fileDesc.fd)
      if not count or count <= 0 then
        break
      end
      done = true
      local data = self.fileDesc:readSync(count) -- should not block
      callback(nil, data)
    end
    return done
  end

  --- Writes data on this serial device.
  -- @tparam string data the data to write.
  -- @tparam[opt] function callback The optional callback.
  -- @return a Promise or nil if a callback has been specified.
  function serial:write(data, callback)
    return self.fileDesc:write(data, nil, callback)
  end

  --- Writes data on this serial device.
  -- @tparam string data the data to write.
  function serial:writeSync(data)
    return self.fileDesc:writeSync(data)
  end

  --- Closes this serial device.
  -- @tparam[opt] function callback The optional callback.
  -- @return a Promise that resolve when closed or nil if a callback has been specified.
  function serial:close(callback)
    return self.fileDesc:close(callback)
  end

  --- Closes this serial device.
  function serial:closeSync()
    return self.fileDesc:closeSync()
  end

  function serial:flush()
    return serialLib.flush(self.fileDesc.fd)
  end

end, function(Serial)

  local FileDescriptor = require('jls.io.FileDescriptor')

  --- Returns a new Serial for the specified name.
  -- @tparam string name The name of the serial device to open.
  -- @tparam table options The serial options.
  -- @tparam number options.baudRate The baud rate.
  -- @tparam number options.dataBits The number of bits transmitted and received.
  -- @tparam number options.stopBits The number of stop bits to be used.
  -- @tparam number options.parity The parity scheme, 0 for no parity.
  -- @return a new Serial or nil.
  function Serial:open(name, options)
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
    return self:new(fileDesc)
  end
end)

