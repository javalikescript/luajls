--- This class enables to create a native process.
-- @module jls.lang.ProcessBuilder
-- @pragma nostrip

--local Path = require('jls.io.Path')
local ProcessHandle = require('jls.lang.ProcessHandle')

local processLib = require('jls.lang.process')
--local logger = require('jls.lang.logger')

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

  --- Sets the process working directory.
  -- With no parameter the function returns the process working directory.
  -- @tparam string dir the process working directory.
  -- @return this ProcessBuilder
  function processBuilder:directory(dir)
    if dir then
      self.dir = dir
      return self
    end
    return self.dir
  end

  --- Sets the process environment.
  -- With no parameter the function returns the process environment.
  -- @tparam table env the process environment.
  -- @return this ProcessBuilder
  function processBuilder:environment(env)
    if env then
      self.env = env
      return self
    else
      return self.env
    end
  end

  --- Redirects the process standard input.
  -- With no parameter the function returns the redirection.
  -- @tparam jls.io.Pipe fd the redirection.
  -- @return this ProcessBuilder
  function processBuilder:redirectInput(fd)
    if fd == nil then
      return self.stdin
    elseif type(fd) == 'table' and fd.fd then
      self.stdin = fd.fd
      return self
    end
    error('Invalid redirection argument')
  end

  --- Redirects the process standard output.
  -- With no parameter the function returns the redirection.
  -- @tparam jls.io.Pipe fd the redirection.
  -- @return this ProcessBuilder
  function processBuilder:redirectOutput(fd)
    if fd == nil then
      return self.stdout
    elseif type(fd) == 'table' and fd.fd then
      self.stdout = fd.fd
      return self
    end
    error('Invalid redirection argument')
  end

  --- Redirects the process standard error.
  -- With no parameter the function returns the redirection.
  -- @tparam jls.io.Pipe fd the redirection.
  -- @return this ProcessBuilder
  function processBuilder:redirectError(fd)
    if fd == nil then
      return self.stderr
    elseif type(fd) == 'table' and fd.fd then
      self.stderr = fd.fd
      return self
    end
    error('Invalid redirection argument')
  end

  --- Starts this ProcessBuilder.
  -- @tparam[opt] function onexit A function that will be called with the exit code when the process ended.
  -- @treturn jls.lang.ProcessHandle The @{jls.lang.ProcessHandle|handle} of the new process
  function processBuilder:start(onexit)
    local pid = processLib.spawn(self, onexit)
    if pid and pid > 0 then
      return ProcessHandle:new(pid)
    end
    return nil
  end

end, function(ProcessBuilder)

  --- Returns the current working directory.
  -- @treturn string the current working directory.
  function ProcessBuilder.getExecutablePath()
    return processLib.exePath()
  end

end)