--[[--
Provide OS file descriptor abstraction.

A FileDescriptor enables to manipulate files, reading from and writing to.

The method are provided both as synchronous and asynchronous.
The synchronous form is suffixed by "Sync".
The asynchronous form takes an optional callback as last argument,
if omitted the method returns a @{jls.lang.Promise}.

@module jls.io.FileDescriptor
@pragma nostrip

@usage
-- synchronous
local fileDesc, err = FileDescriptor.openSync('file_name.txt', 'r')
local data = fileDesc:readSync(1024)
print(data)
fileDesc:closeSync()

-- asynchronous
FileDescriptor.open('file_name.txt', 'r'):next(function(fileDesc)
  return fileDesc:read(256):next(function(data)
    print(data)
    fileDesc:close()
  end)
end)
]]

local class = require('jls.lang.class')
local Promise = require('jls.lang.Promise')
local logger = require('jls.lang.logger')
local event = require('jls.lang.event')
local Path = require('jls.io.Path')

local function deferCallback(cb, err, res)
  if cb then
    event:setTimeout(function()
      cb(err, res)
    end)
  end
end

--- A FileDescriptor class.
-- A FileDescriptor instance represents a file handle.
-- @type FileDescriptor
return require('jls.lang.class').create(function(fileDescriptor)

  function fileDescriptor:initialize(fd)
    if type(fd) == 'number' then
      if fd == 0 then
        fd = io.stdin
      elseif fd == 1 then
        fd = io.stdout
      elseif fd == 2 then
        fd = io.stderr
      end
    end
    self.fd = fd
  end

  --- Closes this file descriptor.
  function fileDescriptor:closeSync()
    self.fd:close()
  end

  --- Flushes all modified data of this file descriptor to the storage device.
  function fileDescriptor:flushSync()
    self.fd:flush()
  end

  fileDescriptor.statSync = class.notImplementedFunction

  --- Reads the specified data from this file descriptor.
  -- @tparam number size The size of the data to read.
  -- @tparam number offset The optional position at which the read is to be performed,
  -- -1 or nil for the current file descriptor position.
  -- @return the data as a string, could be less than the specified size,
  -- nil if the end of file is reached.
  function fileDescriptor:readSync(size, offset)
    if offset and offset >= 0 then
      local pos, err = self.fd:seek('set', offset)
      if not pos then
        return nil, err
      end
    end
    return self.fd:read(size)
  end

  --- Writes the specified data to this file descriptor.
  -- @param data The data to write as a string or an array of string.
  -- @tparam number offset The optional position at which the write is to be performed,
  -- -1 or nil for the current file descriptor position.
  function fileDescriptor:writeSync(data, offset)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('fileDescriptor:writeSync("'..tostring(data)..'", '..tostring(offset)..')')
    end
    if offset and offset >= 0 then
      if logger:isLoggable(logger.DEBUG) then
        logger:debug('seek("set", '..tostring(offset)..')')
      end
      self.fd:seek('set', offset)
    end
    if type(data) == 'string' then
      if logger:isLoggable(logger.DEBUG) then
        logger:debug('writing #'..tostring(#data))
      end
      local status, err = self.fd:write(data)
      if not status then
        return status, err
      end
    elseif type(data) == 'table' then
      for i, d in ipairs(data) do
        local status, err = self.fd:write(d)
        if not status then
          return status, err, i
        end
      end
    else
      error('Invalid write data type')
    end
    return self
  end

  --- Closes this file descriptor.
  -- @tparam[opt] function callback The optional callback.
  function fileDescriptor:close(callback)
    local cb, d = Promise.ensureCallback(callback)
    self:closeSync()
    deferCallback(cb)
    return d
  end

  --- Flushes all modified data of this file descriptor to the storage device.
  -- @tparam[opt] function callback The optional callback.
  function fileDescriptor:flush(callback)
    local cb, d = Promise.ensureCallback(callback)
    self:flushSync()
    deferCallback(cb)
    return d
  end

  fileDescriptor.stat = class.notImplementedFunction

  --- Reads the specified data from this file descriptor.
  -- @tparam number size The size of the data to read.
  -- @tparam number offset The optional position at which the read is to be performed,
  -- @tparam[opt] function callback The optional callback.
  -- @return a Promise or nil if a callback has been specified.
  -- @usage
  --fd:read(1024):then(function(data)
  --  -- process the data
  --end)
  -- -- or when using a callback
  --fd:read(1024, nil, function(err, data)
  --  if not err
  --    -- process the data
  --  end
  --end)
  function fileDescriptor:read(size, offset, callback)
    if type(offset) == 'function' then
      callback = offset
      offset = nil
    end
    local cb, d = Promise.ensureCallback(callback)
    local data = self:readSync(size, offset)
    deferCallback(cb, nil, data)
    return d
  end

  --- Writes the specified data to this file descriptor.
  -- @param data The data to write as a string or an array of string.
  -- @tparam number offset The optional position at which the write is to be performed,
  -- -1 or nil for the current file descriptor position.
  -- @tparam[opt] function callback an optional callback function to use in place of promise.
  -- @return a promise that resolves once the data has been wrote.
  function fileDescriptor:write(data, offset, callback)
    if type(offset) == 'function' then
      callback = offset
      offset = nil
    end
    local cb, d = Promise.ensureCallback(callback)
    local _, err = self:writeSync(data, offset)
    deferCallback(cb, err)
    return d
  end

end, function(FileDescriptor)
  --- Returns a new FileDescriptor for the specified path name.
  -- @param path The file path as a string or a @{Path}.
  -- @tparam string mode The mode to be used to open the file 'r', 'w' or 'a' with an optional '+'.
  -- @return a new FileDescriptor or nil.
  -- @usage
  --local fileDesc, err = FileDescriptor.openSync(pathName, 'r')
  function FileDescriptor.openSync(path, mode)
    mode = mode or 'r'
    mode = mode..'b'
    local fd, err = io.open(Path.asNormalizedPath(path), mode)
    if fd then
      return FileDescriptor:new(fd)
    end
    return nil, err
  end

  --- Returns a new FileDescriptor for the specified path name.
  -- @param path The file path as a string or a @{Path}.
  -- @tparam string mode The mode to be used to open the file, 'r' or 'w'.
  -- @tparam[opt] function callback an optional callback function to use in place of promise.
  -- @return a promise that resolves to a new FileDescriptor.
  function FileDescriptor.open(path, mode, callback)
    local cb, d = Promise.ensureCallback(callback)
    local fd, err = FileDescriptor.openSync(Path.asNormalizedPath(path), mode)
    deferCallback(cb, err, fd)
    return d
  end

end)
