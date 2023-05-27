--- Provide a simple file stream handler.
-- @module jls.io.streams.FileStreamHandler
-- @pragma nostrip

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local File = require('jls.io.File')
local FileDescriptor = require('jls.io.FileDescriptor')

--- This class allows to write a stream into and from a file.
-- @type FileStreamHandler
return require('jls.lang.class').create('jls.io.StreamHandler', function(fileStreamHandler)

  -- TODO move sync to first place

  --- Creates a @{StreamHandler} that will write to a file.
  -- @tparam jls.io.File file The file to create
  -- @tparam[opt] boolean overwrite true to indicate that existing file must be re created
  -- @tparam[opt] function onClose a function that will be called when the stream has ended
  -- @tparam[opt] boolean openOnData true to indicate that the file shall be opened on first data received
  -- @tparam[opt] boolean sync true to indicate that the write shall be synchronous
  -- @function FileStreamHandler:new
  function fileStreamHandler:initialize(file, overwrite, onClose, openOnData, sync, mode)
    self.file = File.asFile(file)
    if not overwrite and self.file:isFile() then
      error('File exists')
    end
    if type(onClose) == 'function' then
      self.onClose = onClose
    end
    self.mode = mode or 'w'
    self.async = not sync
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
      if self.async then
        return self.fd:write(data)
      end
      local status, err = self.fd:writeSync(data)
      if not status then
        self:onError(err)
      end
    else
      return self:close():next(function()
        return self:onClose()
      end)
    end
  end

  function fileStreamHandler:onError(err)
    self:close()
    self.file:delete()
  end

  function fileStreamHandler:close()
    local fd = self.fd
    if fd then
      self.fd = nil
      if self.async then
        return fd:close()
      end
      fd:closeSync()
    end
    return Promise.resolve()
  end

end, function(FileStreamHandler)

  FileStreamHandler.DEFAULT_BLOCK_SIZE = 4096

  -- Reads the specified file descriptor using the stream handler.
  -- @param fd The file descriptor to read.
  -- @param stream The stream handler to use with the file content.
  -- @tparam[opt] number offset The offset.
  -- @tparam[opt] number length The length to read.
  -- @tparam[opt] number size The read block size.
  -- @return a promise that resolves once the file has been fully read.
  local function readFd(fd, sh, offset, length, size, callback)
    logger:finer('readFd(?, ?, %s, %s, %s)', offset, length, size)
    local cb, d = Promise.ensureCallback(callback)
    if not size then
      size = FileStreamHandler.DEFAULT_BLOCK_SIZE
    end
    local function readCallback(err, data)
      --logger:info('readCallback('..type(err)..', '..type(data)..')')
      if err then
        sh:onError(err)
        cb(err)
      else
        local r = sh:onData(data)
        if data then
          local l = #data
          if offset then
            offset = offset + l
          end
          if length then
            length = length - l
            --if length > 1048576 and logger:isLoggable(logger.FINE) then
            --  logger:logopt(logger.FINE, 'readCallback() remaining length '..tostring(length))
            --end
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
            if Promise:isInstance(r) then
              r:next(function()
                fd:read(size, offset, readCallback)
              end, function(reason)
                logger:fine('readCallback() onData() error, %s', reason)
                sh:onError(reason)
                cb(reason)
              end)
            else
              fd:read(size, offset, readCallback)
            end
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
  -- @tparam[opt] number size The read block size.
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
    return FileStreamHandler.read(file, stream, nil, nil, size)
  end

  local function readFdSync(fd, sh, offset, length, size)
    if not size then
      size = FileStreamHandler.DEFAULT_BLOCK_SIZE
    end
    while true do
      if length and size > length then
        size = length
      end
      local data, err = fd:readSync(size, offset)
      if err then
        sh:onError(err)
        break
      else
        local r = sh:onData(data)
        if Promise:isInstance(r) then
          logger:warn('readFdSync() unsupported onData() promise return')
        end
        if data then
          local l = #data
          if offset then
            offset = offset + l
          end
          if length then
            length = length - l
            if length <= 0 then
              l = 0
            end
          end
          if l == 0 then
            sh:onData()
            break
          end
        else
          break
        end
      end
    end
  end

  --- Reads synchronously the specified file using the stream handler.
  -- @param file The file to read.
  -- @param stream The stream handler to use with the file content.
  -- @tparam[opt] number offset The offset.
  -- @tparam[opt] number length The length to read.
  -- @tparam[opt] number size The read block size.
  function FileStreamHandler.readSync(file, stream, offset, length, size)
    local sh = FileStreamHandler.ensureStreamHandler(stream)
    local fd, err = FileDescriptor.openSync(file, 'r')
    if not fd then
      sh:onError(err)
    else
      readFdSync(fd, sh, offset, length, size)
      fd:closeSync()
    end
  end

  function FileStreamHandler.readAllSync(file, stream, size)
    FileStreamHandler.readSync(file, stream, nil, nil, size)
  end

end)
