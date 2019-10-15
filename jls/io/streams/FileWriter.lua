--- Provide a simple file writer as a stream.
-- @module jls.io.streams.FileWriter
-- @pragma nostrip

local File = require('jls.io.File')
local FileDescriptor = require('jls.io.FileDescriptor')
local StreamHandler = require('jls.io.streams.StreamHandler')

--- This class allows to write a stream into a file.
-- @type FileWriter
return require('jls.lang.class').create(StreamHandler, function(fileWriter)

  --- Creates a @{StreamHandler} that will write to a file.
  -- @tparam function cb the callback
  -- @function FileWriter:new
  function fileWriter:initialize(file, overwrite, onClose)
    self.file = File.asFile(file)
    if not overwrite and self.file:isFile() then
      error('File exists')
    end
    local fd, err = FileDescriptor.openSync(self.file, 'w')
    if err then
      error(err)
    end
    self.fd = fd
    if type(onClose) == 'function' then
      self.onClose = onClose
    end
  end

  function fileWriter:getFile()
    return self.file
  end

  function fileWriter:onClose()
  end

  function fileWriter:onData(data)
    if data then
      self.fd:writeSync(data)
    else
      self:close()
      self:onClose()
    end
  end

  function fileWriter:onError(err)
    self:close()
    self.file:delete()
  end

  function fileWriter:close()
    if self.fd then
      self.fd:closeSync()
      self.fd = nil
    end
  end

end, function(FileWriter)

  function FileWriter.streamFile(file, stream, blockSize)
    if type(blockSize) ~= 'number' then
      blockSize = 1024
    end
    local cb = StreamHandler.ensureCallback(stream)
    local file = File.asFile(file)
    if not file:isFile() then
      error('File does not exist')
    end
    -- TODO handle errors when opening, reading and closing
    local fd = FileDescriptor.openSync(file)
    local onRead
    onRead = function(err, data)
      if err or not data then
        fd:closeSync()
        fd = nil
      end
      local r = cb(err, data)
      if r~= false and fd then
        fd:read(blockSize, -1, onRead)
      end
      return r
    end
    fd:read(blockSize, -1, onRead)
  end

end)
