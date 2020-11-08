local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local FileDescriptor = require('jls.io.FileDescriptor')

-- Reads from a file descriptor and writes to the specified stream.
local function writeFileDescriptor(fd, stream, readBlockSize, cb)
  if type(readBlockSize) ~= 'number' then
    readBlockSize = 1024
  end
  local writeCallback
  local function readCallback(err, data)
    if err then
      cb(err)
    elseif data then
      if logger:isLoggable(logger.FINER) then
        logger:finer('writeFileDescriptor() => read #'..tostring(#data))
      end
      stream:write(data, writeCallback)
    else
      cb()
    end
  end
  writeCallback = function(err)
    if logger:isLoggable(logger.FINER) then
      logger:finer('writeFileDescriptor() => writeCallback('..tostring(err)..')')
    end
    if err then
      cb(err)
    else
      fd:read(readBlockSize, nil, readCallback)
    end
  end
  writeCallback()
end

-- Registers the specified file descriptor to write the body.
local function setMessageBodyFileDescriptor(httpMessage, fdProvider, readBlockSize, completionCallback)
  if type(readBlockSize) == 'function' then
    completionCallback = readBlockSize
    readBlockSize = nil
  end
  if logger:isLoggable(logger.FINE) then
    logger:fine('setMessageBodyFileDescriptor(?, '..tostring(readBlockSize)..')')
  end
  function httpMessage:writeBody(stream, callback)
    if logger:isLoggable(logger.FINE) then
      logger:fine('setMessageBodyFileDescriptor() => response:writeBody()')
    end
    local pcb, promise = Promise.ensureCallback(callback)
    local fd, cb
    if type(fdProvider) == 'function' then
      local err
      fd, err = fdProvider()
      if err or not fd then
        pcb(err or 'Unable to get file descriptior')
        return promise
      end
    else
      fd = fdProvider
    end
    if type(completionCallback) == 'function' then
      cb = function(err)
        completionCallback(fd, err)
        pcb(err)
      end
    else
      cb = pcb
    end
    writeFileDescriptor(fd, stream, readBlockSize, cb)
    return promise
  end
end

-- Registers the specified file to write the body.
local function setMessageBodyFile(httpMessage, file, readBlockSize)
  setMessageBodyFileDescriptor(httpMessage, function()
    return FileDescriptor.openSync(file)
  end, readBlockSize, function(fd)
    fd:closeSync()
  end)
end

local function setMessageBodyFileSync(response, file, size)
  local body = file:readAll()
  if body then
    response:setBody(body)
  end
end

return setMessageBodyFile
