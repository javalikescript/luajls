--- Provide a simple file stream handler.
-- @module jls.io.streams.FileStreamHandler
-- @pragma nostrip

local Promise = require('jls.lang.Promise')
local File = require('jls.io.File')
local FileDescriptor = require('jls.io.FileDescriptor')

--- This class allows to write a stream into and from a file.
-- @type FileStreamHandler
return require('jls.lang.class').create('jls.io.streams.StreamHandler', function(fileStreamHandler)

  --- Creates a @{StreamHandler} that will write to a file.
  -- @tparam jls.io.File file The file to create
  -- @tparam[opt] boolean overwrite true to indicate that existing file must be re created
  -- @tparam[opt] function onClose a function that will be called when the stream has ended
  -- @tparam[opt] boolean openOnData true to indicate that the file shall be opened on first data received
  -- @function FileStreamHandler:new
  function fileStreamHandler:initialize(file, overwrite, onClose, openOnData)
    self.file = File.asFile(file)
    if not overwrite and self.file:isFile() then
      error('File exists')
    end
    if type(onClose) == 'function' then
      self.onClose = onClose
    end
    if openOnData then
      self.openOnData = true
    else
      self.openOnData = false
      self:openFile()
    end
  end

  function fileStreamHandler:openFile()
    local fd, err = FileDescriptor.openSync(self.file, 'w')
    if err then
      error(err)
    end
    self.fd = fd
  end

  function fileStreamHandler:getFile()
    return self.file
  end

  function fileStreamHandler:onClose()
  end

  function fileStreamHandler:onData(data)
    if data then
      if self.openOnData then
        self.openOnData = false
        self:openFile()
      end
      self.fd:writeSync(data) -- TODO handle errors
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

  local DEFAULT_BLOCK_SIZE = 4096

  local function readFd(fd, sh, offset, length, size, callback)
    --logger:info('readFd(?, ?, '..tostring(offset)..', '..tostring(length)..', '..tostring(size)..')')
    local cb, d = Promise.ensureCallback(callback)
    if not size then
      size = DEFAULT_BLOCK_SIZE
    end
    local function readCallback(err, data)
      --logger:info('readCallback('..type(err)..', '..type(data)..')')
      if err then
        sh:onError(err)
        cb(err)
      else
        if sh:onData(data) ~= false and data then
          local l = #data
          if length then
            length = length - l
            if length <= 0 then
              l = 0
            elseif size > length then
              size = length
            end
          end
          if l == 0 then
            sh:onData()
            cb()
          else
            if offset then
              offset = offset + l
            end
            fd:read(size, offset, readCallback)
          end
        else
          cb()
        end
      end
    end
    if length and size > length then
      size = length
    end
    if size <= 0 then
      readCallback()
    else
      fd:read(size, offset, readCallback)
    end
    return d
  end

  --- Reads the specified file using the stream handler.
  -- @param file The file to read.
  -- @param stream The stream handler to use with the file content.
  -- @tparam[opt] number offset The offset.
  -- @tparam[opt] number length The length to read.
  -- @tparam[opt] number size The read block size, default is 4096.
  -- @return a promise that resolves once the file has been fully read.
  function FileStreamHandler.read(file, stream, offset, length, size)
    local sh = FileStreamHandler.ensureStreamHandler(stream)
    FileDescriptor.open(file, 'r'):next(function(fd)
      return readFd(fd, sh, offset, length, size):next(function()
        return fd:close()
      end, function(err)
        fd:closeSync()
        return Promise.reject(err)
      end)
    end, function(err)
      sh:onError(err)
      return Promise.reject(err)
    end)
  end

  function FileStreamHandler.readAll(file, stream, size)
    FileStreamHandler.read(file, stream, nil, nil, size)
  end

  local function readFdSync(fd, sh, size)
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
        if sh:onData(data) == false or not data then
          break
        elseif #data == 0 then
          sh:onData()
          break
        end
      end
    end
  end

  --- Reads synchronously the specified file using the stream handler.
  -- @param file The file to read.
  -- @param stream The stream handler to use with the file content.
  -- @tparam[opt] number size The read block size, default is 4096.
  function FileStreamHandler.readSync(file, stream, size)
    local sh = FileStreamHandler.ensureStreamHandler(stream)
    local fd, err = FileDescriptor.openSync(file, 'r')
    if not fd then
      sh:onError(err)
    else
      readFdSync(fd, sh, size)
      fd:closeSync()
    end
  end

  function FileStreamHandler.readAllSync(file, stream, size)
    FileStreamHandler.readSync(file, stream, size)
  end

end)
