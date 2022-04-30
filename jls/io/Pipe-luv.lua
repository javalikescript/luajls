--[[--
Provide pipe and named pipe abstraction.

The Pipe class provides inter-process stream communication.
The Pipe class also provides named pipe.

Note: Named pipes are only available with the _luv_ module.

@module jls.io.Pipe
@pragma nostrip
]]

local luvLib = require('luv')

local class = require('jls.lang.class')
local Promise = require('jls.lang.Promise')
local logger = require('jls.lang.logger')
local luv_stream = require('jls.lang.luv_stream')
local close, read_start, read_stop, write = luv_stream.close, luv_stream.read_start, luv_stream.read_stop, luv_stream.write

--- The Pipe class.
-- @type Pipe
return class.create(function(pipe, _, Pipe)

  --- Creates a new Pipe.
  -- @function Pipe:new
  function pipe:initialize(ipc)
    self.fd = luvLib.new_pipe(ipc == true)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('Pipe:new() fd: '..tostring(self.fd))
    end
  end

  --- Binds this pipe to the specified name.
  -- @tparam string name the name of the pipe.
  -- @tparam[opt] number backlog the connection queue size, default is 32.
  -- @treturn jls.lang.Promise a promise that resolves once the pipe server is bound.
  function pipe:bind(name, backlog)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('pipe:bind('..tostring(name)..', '..tostring(backlog)..')')
    end
    -- status, err
    local _, err = self.fd:bind(name)
    if err then
      if logger:isLoggable(logger.FINE) then
        logger:fine('pipe:bind('..tostring(name)..', '..tostring(backlog)..') bind in error, '..tostring(err))
      end
      return Promise.reject(err)
    end
    _, err = luvLib.listen(self.fd, backlog or 32, function(err)
      assert(not err, err) -- TODO Handle errors
      self:handleAccept()
    end)
    if err then
      if logger:isLoggable(logger.FINE) then
        logger:fine('pipe:bind('..tostring(name)..', '..tostring(backlog)..') listen in error, '..tostring(err))
      end
      return Promise.reject(err)
    end
    return Promise.resolve()
  end

  function pipe:handleAccept()
    local fd = self:pipeAccept()
    if logger:isLoggable(logger.FINEST) then
      logger:finest('pipe:handleAccept() fd: '..tostring(self.fd)..', accept: '..tostring(fd))
    end
    if fd then
      local p = class.makeInstance(Pipe)
      p.fd = fd
      self:onAccept(p)
    end
  end

  function pipe:pipeAccept()
    logger:finest('pipe:pipeAccept()')
    local fd = luvLib.new_pipe(false)
    local status, err = luvLib.accept(self.fd, fd)
    if status then
      return fd
    end
    return nil, (err or 'Accept fails')
  end

  --- Accepts a new pipe client.
  -- This method should be overriden, the default implementation closes the client.
  -- @param pipeClient the pipe client to accept.
  function pipe:onAccept(pipeClient)
    logger:fine('pipe:onAccept() => closing')
    pipeClient:close()
  end

  --- Connects this pipe to the specified name.
  -- @tparam string name the name of the pipe.
  -- @tparam[opt] function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the pipe is connected.
  function pipe:connect(name, callback)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('pipe:connect('..tostring(name)..')')
    end
    local cb, d = Promise.ensureCallback(callback)
    self.fd:connect(name, cb)
    return d
  end

  --- Opens an existing file descriptor as this pipe.
  -- @tparam number f the file descriptor as an integer
  function pipe:open(f) -- f as integer
    -- status, err
    return self.fd:open(f)
  end

  --- Starts reading data on this pipe.
  -- @param stream the stream reader, could be a function or a @{jls.io.StreamHandler}.
  function pipe:readStart(stream)
    return read_start(self.fd, stream)
  end

  --- Stops reading data on this pipe.
  function pipe:readStop()
    return read_stop(self.fd)
  end

  --- Writes data on this pipe.
  -- @tparam string data the data to write.
  -- @tparam function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the data has been written.
  function pipe:write(data, callback)
    return write(self.fd, data, callback)
  end

  --- Makes the pipe writable or readable by all users.
  -- Enables access to the pipe from other processes.
  -- @tparam string mode the mode to set, could be 'r', 'w' or 'rw'
  function pipe:chmod(mode)
    -- status, err
    return self.fd:chmod(mode)
  end

  --- Closes this pipe.
  -- @tparam function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the pipe is closed.
  function pipe:close(callback)
    local stream = self.fd
    self.fd = nil
    return close(stream, callback)
  end

  function pipe:isClosed()
    return not self.fd
  end

  -- Shutdowns the outgoing (write) side of a duplex stream.
  function pipe:shutdown(callback)
    logger:finest('pipe:shutdown()')
    local cb, d = Promise.ensureCallback(callback)
    if self.fd then
      luvLib.shutdown(self.fd, cb)
    else
      cb()
    end
    return d
  end

  local index = 0
  function Pipe.generateUniqueName(name)
    local currentTimeMillis = require('jls.lang.system').currentTimeMillis
    local formatInteger = require('jls.util.strings').formatInteger
    index = (index + 1) % 262144
    return name..'-'..formatInteger(luvLib.os_getpid(), 64)..'-'..formatInteger(index, 64)..'-'..formatInteger(currentTimeMillis(), 64)
  end

  local PIPE_PREFIX
  if require('jls.lang.system').isWindows() then
    PIPE_PREFIX = '\\\\.\\pipe\\'
  else
    PIPE_PREFIX = os.getenv('TMPDIR') or '/tmp/'
  end

  function Pipe.normalizePipeName(name, unique)
    if unique then
      return PIPE_PREFIX..Pipe.generateUniqueName(name)
    end
    return PIPE_PREFIX..name
  end

end)
