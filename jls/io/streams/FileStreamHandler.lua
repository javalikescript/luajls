--- Provide a simple file stream handler.
-- @module jls.io.streams.FileStreamHandler
-- @pragma nostrip

local File = require('jls.io.File')
local FileDescriptor = require('jls.io.FileDescriptor')
local StreamHandler = require('jls.io.streams.StreamHandler')
local Promise = require('jls.lang.Promise')

--- This class allows to write a stream into and from a file.
-- @type FileStreamHandler
return require('jls.lang.class').create(StreamHandler, function(fileStreamHandler)

  --- Creates a @{StreamHandler} that will write to a file.
  -- @tparam jls.io.File file The file to create
  -- @tparam[opt] boolean overwrite true to indicate that existing file must be re created
  -- @tparam[opt] function onClose a function that will be called when the stream has ended
  -- @function FileStreamHandler:new
  function fileStreamHandler:initialize(file, overwrite, onClose)
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

  function fileStreamHandler:getFile()
    return self.file
  end

  function fileStreamHandler:onClose()
  end

  function fileStreamHandler:onData(data)
    if data then
      self.fd:writeSync(data)
    else
      self:close()
      self:onClose()
    end
  end

  function fileStreamHandler:onError(err)
    self:close()
    self.file:delete()
  end

  function fileStreamHandler:close()
    if self.fd then
      self.fd:closeSync()
      self.fd = nil
    end
  end

end, function(FileStreamHandler)

  local DEFAULT_BLOCK_SIZE = 1024

  local function readAllFd(fd, sh, size, callback)
    --local sh = StreamHandler.ensureStreamHandler(stream)
    local cb, d = Promise.ensureCallback(callback)
    if not size then
      size = DEFAULT_BLOCK_SIZE
    end
    local readCallback
    readCallback = function(err, data)
      if err then
        sh:onError(err)
        cb(err)
      else
        if sh:onData(data) ~= false and data and #data > 0 then
          fd:read(size, nil, readCallback)
        else
          cb()
        end
      end
    end
    fd:read(size, nil, readCallback)
    return d
  end

  --- Reads the specified file using the stream handler.
  -- @param file The file to read.
  -- @param stream The stream handler to use with the file content.
  -- @tparam[opt] number size The read block size, default is 1024.
  -- @return a promise that resolves once the file has been fully read.
  function FileStreamHandler.readAll(file, stream, size)
    local sh = StreamHandler.ensureStreamHandler(stream)
    FileDescriptor.open(file, 'r'):next(function(fd)
      return readAllFd(fd, sh, size):next(function()
        return fd:close()
      end, function(err)
        fd:closeSync()
      end)
    end, function(err)
      sh:onError(err)
    end)
  end

  local function readAllFdSync(fd, sh, size)
    --local sh = StreamHandler.ensureStreamHandler(stream)
    if not size then
      size = DEFAULT_BLOCK_SIZE
    end
    while true do
      local data, err = fd:readSync(size)
      if err then
        sh:onError(err)
        break
      else
        if sh:onData(data) == false or not data or #data == 0 then
          break
        end
      end
    end
  end

  --- Reads synchronously the specified file using the stream handler.
  -- @param file The file to read.
  -- @param stream The stream handler to use with the file content.
  -- @tparam[opt] number size The read block size, default is 1024.
  function FileStreamHandler.readAllSync(file, stream, size)
    local sh = StreamHandler.ensureStreamHandler(stream)
    local fd, err = FileDescriptor.openSync(file, 'r')
    if not fd then
      sh:onError(err)
    else
      readAllFdSync(fd, sh, size)
      fd:closeSync()
    end
  end

end)
