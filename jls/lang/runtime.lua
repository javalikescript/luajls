--- The Runtime module provides interaction with the underlying OS.
-- @module jls.lang.runtime

local logger = require('jls.lang.logger')

local process = require('jls.lang.process')
local Path = require('jls.io.Path')
local ProcessHandle = require('jls.lang.ProcessHandle')

local runtime = {}

-- look for lua path
if arg then
  for i = 0, -10, -1 do
    if arg[i] then
      runtime.luaPath = arg[i]
    else
      break
    end
  end
end
if not runtime.luaPath then
  runtime.luaPath = 'lua' -- fallback
end

--- Executes the specified command and arguments in a separate process with the specified environment and working directory.
-- @param pathOrArgs Array of strings specifying the command-line arguments.
-- The first argument is the name of the executable file.
-- @param env Array of key=values specifying the environment strings.
-- If undefined, the new process inherits the environment of the parent process.
-- @param dir The working directory of the subprocess, or undefined
-- if the subprocess should inherit the working directory of the current process.
function runtime.exec(pathOrArgs, env, dir)
  if type(pathOrArgs) == 'string' then
    pathOrArgs = Path.asPathName(pathOrArgs)
  elseif type(pathOrArgs) == 'table' and pathOrArgs[1] then
    pathOrArgs[1] = Path.asPathName(pathOrArgs[1])
  end
  if dir then
    dir = Path.asPathName(dir)
  end
  local pid = process.execute(pathOrArgs, env, dir)
  if pid then
    return ProcessHandle:new(pid)
  end
  return nil
end

--- Terminates the program and returns a value to the OS.
-- @param code The exit code to return to the OS.
function runtime.exit(code)
  return os.exit(code, true)
end

--- Runs the garbage collector. 
function runtime.gc()
  collectgarbage('collect')
end

--- Forcibly terminates the program and returns a value to the OS.
-- @param code The exit code to return to the OS.
function runtime.halt(code)
  return os.exit(code, false)
end

return runtime