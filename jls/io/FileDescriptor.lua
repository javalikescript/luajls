local FileDescriptor = require('jls.lang.loader').requireOne('jls.io.FileDescriptor-luv', 'jls.io.FileDescriptor-')
local Promise = require('jls.lang.Promise')

function FileDescriptor.prototype:readAll(stream, size, callback)
  local cb, d = Promise.ensureCallback(callback)
  if not size then
    size = 1024
  end
  local readCallback
  readCallback = function(err, data)
    if err then
      stream:onError(err)
      cb(err)
    else
      if stream:onData(data) ~= false and data and #data > 0 then
        self:read(size, nil, readCallback)
      else
        cb()
      end
    end
  end
  self:read(size, nil, readCallback)
  return d
end

function FileDescriptor.readAll(file, stream, size)
  FileDescriptor.open(file, 'r'):next(function(fd)
    return fd:readAll(stream, size):next(function()
      return fd:close()
    end, function(err)
      fd:closeSync()
    end)
  end, function(err)
    stream:onError(err)
  end)
end

function FileDescriptor.prototype:readSyncAll(stream, size)
  if not size then
    size = 1024
  end
  while true do
    local data, err = self:readSync(size)
    if err then
      stream:onError(err)
      break
    else
      if stream:onData(data) == false or not data or #data == 0 then
        break
      end
    end
  end
end

function FileDescriptor.readSyncAll(file, stream, size)
  local fd, err = FileDescriptor.openSync(file, 'r')
  if not fd then
    stream:onError(err)
  else
    fd:readSyncAll(stream, size)
    fd:closeSync()
  end
end

return FileDescriptor
