
local luvLib = require('luv')

local Promise = require('jls.lang.Promise')
local Path = require('jls.io.Path')

local function adaptStat(st)
  -- make a stat table compatible with lfs
  if st then
    --st.moden = st.mode -- not used
    st.mode = st.type
    if st.mtime then
      st.modification = st.mtime.sec
    end
  end
  return st
end

local OPEN_MODE = tonumber('644', 8)

return require('jls.lang.class').create(function(fileDescriptor)

  function fileDescriptor:initialize(fd)
    self.fd = fd
  end

  function fileDescriptor:closeSync()
    --luvLib.fs_fsync(self.fd)
    return luvLib.fs_close(self.fd)
  end

  function fileDescriptor:flushSync()
    return luvLib.fs_fsync(self.fd)
  end

  function fileDescriptor:statSync()
    return adaptStat(luvLib.fs_fstat(self.fd))
  end

  function fileDescriptor:readSync(size, offset)
    offset = offset or -1 -- use offset by default
    local data, err = luvLib.fs_read(self.fd, size, offset)
    if data and #data == 0 then
      return nil, err
    end
    return data, err
  end

  function fileDescriptor:writeSync(data, offset)
    offset = offset or -1 -- use offset by default
    return luvLib.fs_write(self.fd, data, offset)
  end

  function fileDescriptor:close(callback)
    local cb, d = Promise.ensureCallback(callback)
    -- luvLib.fs_fsync(self.fd, function(err)
    --   if err then
    --     cb(err)
    --   else
    --     luvLib.fs_close(self.fd, cb)
    --   end
    -- end)
    luvLib.fs_close(self.fd, cb)
    return d
  end

  function fileDescriptor:flush(callback)
    local cb, d = Promise.ensureCallback(callback)
    luvLib.fs_fsync(self.fd, cb)
    return d
  end

  function fileDescriptor:stat(callback)
    local cb, d = Promise.ensureCallback(callback)
    luvLib.fs_fstat(self.fd, function (err, st)
      cb(err, adaptStat(st))
    end)
    return d
  end

  function fileDescriptor:read(size, offset, callback)
    local cb, d = Promise.ensureCallback(callback)
    offset = offset or -1 -- use offset by default
    luvLib.fs_read(self.fd, size, offset, function(err, data)
      if err then
        cb(err)
      else
        if data and #data == 0 then
          cb()
        else
          cb(nil, data)
        end
      end
    end)
    return d
  end

  function fileDescriptor:write(data, offset, callback)
    local cb, d = Promise.ensureCallback(callback)
    offset = offset or -1 -- use offset by default
    luvLib.fs_write(self.fd, data, offset, cb)
    return d
  end

end, function(FileDescriptor)

  function FileDescriptor.openSync(path, mode)
    mode = mode or 'r'
    local fd, err = luvLib.fs_open(Path.asPathName(path), mode, OPEN_MODE)
    if fd then
      return FileDescriptor:new(fd)
    end
    return nil, err
  end

  function FileDescriptor.open(path, mode, callback)
    mode = mode or 'r'
    local cb, d = Promise.ensureCallback(callback)
    luvLib.fs_open(Path.asPathName(path), mode, OPEN_MODE, function(err, fd)
      if fd and not err then
        cb(nil, FileDescriptor:new(fd))
      else
        cb(err)
      end
    end)
    return d
  end

end)
