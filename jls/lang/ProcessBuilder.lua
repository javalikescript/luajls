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
  -- @return a new ProcessBuilder
  -- @usage
  --local pb = ProcessBuilder:new('ls', '-ltr')
  --pb:start()
  function processBuilder:initialize(...)
    self:command(...)
  end
  
  function processBuilder:command(...)
    local args = {...}
    if #args == 0 then
      return self.cmd
    end
    if #args == 1 and type(args[1]) == 'table' then
      self.cmd = args[1]
    else
      self.cmd = args
    end
    return self
  end
  
  function processBuilder:directory(dir)
    if dir then
      self.dir = dir
      return self
    else
      return self.dir
    end
  end
  
  function processBuilder:environment(env)
    if env then
      self.env = env
      return self
    else
      return self.env
    end
  end
  
  function processBuilder:redirectInput(fd)
    self.stdin = fd.fd
  end
  
  function processBuilder:redirectOutput(fd)
    self.stdout = fd.fd
  end
  
  --- Starts this ProcessBuilder.
  -- @treturn jls.lang.ProcessHandle a handle of the new process
  function processBuilder:start(onexit)
    local pid = processLib.spawn(self, onexit)
    if pid and pid > 0 then
      return ProcessHandle:new(pid)
    end
    return nil
  end

end, function(ProcessBuilder)
  
  function ProcessBuilder.getExecutablePath()
    return processLib.exePath()
  end

end)