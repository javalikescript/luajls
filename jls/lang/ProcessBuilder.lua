--[[--
This class enables to create a native process.

Note: The only full implementation is based on libuv

@module jls.lang.ProcessBuilder
@pragma nostrip
]]

local ProcessHandle = require('jls.lang.ProcessHandle')

local function capitalize(s)
  return string.upper(string.sub(s, 1, 1))..string.sub(s, 2)
end

local function createGetSetMethod(name)
  return function(self, ...)
    if select('#', ...) == 0 then
      return self['get'..capitalize(name)](self)
    end
    return self['set'..capitalize(name)](self, ...)
  end
end

local function addGetSetMethod(self, name)
  self[name] = createGetSetMethod(name)
  return self
end


--- A ProcessBuilder class.
-- @type ProcessBuilder
return require('jls.lang.class').create(function(processBuilder)

  --- Creates a new ProcessBuilder.
  -- @function ProcessBuilder:new
  -- @tparam string ... the process executable path and arguments
  -- @return a new ProcessBuilder
  -- @usage
  --local pb = ProcessBuilder:new('ls', '-ltr')
  --pb:start()
  function processBuilder:initialize(...)
    self:command(...)
  end

  --- Sets the process executable path and arguments.
  -- With no parameter the function returns the process executable path and arguments.
  -- @tparam string ... the process executable path and arguments as strings
  -- @return this ProcessBuilder
  function processBuilder:command(...)
    local argCount = select('#', ...)
    if argCount == 0 then
      return self.cmd
    end
    if argCount == 1 and type(...) == 'table' then
      self.cmd = (...)
    else
      self.cmd = {...}
    end
    return self
  end

  --- Returns the process working directory.
  -- @treturn string the process working directory or nil.
  function processBuilder:getDirectory()
    return self.dir
  end

  --- Sets the process working directory.
  -- @tparam string dir the process working directory.
  -- @return this ProcessBuilder
  function processBuilder:setDirectory(dir)
    self.dir = dir
    return self
  end

  --- Returns the process environment.
  -- @treturn table the process environment.
  function processBuilder:getEnvironment()
    return self.env
  end

  --- Sets the process environment.
  -- @tparam table env the process environment.
  -- @return this ProcessBuilder
  function processBuilder:setEnvironment(env)
    self.env = env
    return self
  end

  --- Returns the process standard input redirection.
  -- @return the redirection
  function processBuilder:getRedirectInput()
    return self.stdin
  end

  --- Redirects the process standard input.
  -- @param[opt] fd the file descriptor or pipe to redirect from.
  -- @return this ProcessBuilder
  -- @usage
  --pb:setRedirectInput(system.input)
  function processBuilder:setRedirectInput(fd)
    self.stdin = fd
    return self
  end

  --- Returns the process standard output redirection.
  -- @return the redirection
  function processBuilder:getRedirectOutput()
    return self.stdout
  end

  --- Redirects the process standard output.
  -- If not provided, the standard output will be discarded, redirected to null.
  -- @param[opt] fd the file descriptor or pipe to redirect to.
  -- @return this ProcessBuilder
  -- @usage
  --local fd = FileDescriptor.openSync(tmpFile, 'w')
  --local pb = ProcessBuilder:new({'lua', '-e', 'io.write("Hello")'})
  --pb:setRedirectOutput(fd)
  function processBuilder:setRedirectOutput(fd)
    self.stdout = fd
    return self
  end

  --- Returns the process standard error redirection.
  -- @return the redirection
  function processBuilder:getRedirectError()
    return self.stderr
  end

  --- Redirects the process standard error.
  -- @param[opt] fd the file descriptor or pipe to redirect to.
  -- @return this ProcessBuilder
  -- @usage
  --local pb = ProcessBuilder:new({'lua', '-e', 'io.stderr:write("Hello")'})
  --local pipe = Pipe:new()
  --pb:setRedirectError(pipe)
  function processBuilder:setRedirectError(fd)
    self.stderr = fd
    return self
  end

  addGetSetMethod(processBuilder, 'directory')
  addGetSetMethod(processBuilder, 'environment')
  addGetSetMethod(processBuilder, 'redirectInput')
  addGetSetMethod(processBuilder, 'redirectOutput')
  addGetSetMethod(processBuilder, 'redirectError')

  --- Starts this ProcessBuilder.
  -- @treturn jls.lang.ProcessHandle The @{jls.lang.ProcessHandle|handle} of the new process
  function processBuilder:start(callback)
    local processHandle = ProcessHandle.build(self)
    -- for compatibility
    if processHandle and type(callback) == 'function' then
      processHandle:ended():next(callback)
    end
    return processHandle
  end

end, function(ProcessBuilder)

  -- TODO remove as deprecated
  ProcessBuilder.getExecutablePath = ProcessHandle.getExecutablePath

end)