--- The Runtime module provides interaction with the underlying OS.
-- @module jls.lang.runtime

local processLib = require('jls.lang.process')
local Promise = require('jls.lang.Promise')

local runtime = {}

--- Executes the specified command and arguments in a separate process with the specified environment and working directory.
-- @param command Array of strings specifying the command-line arguments.
-- The first argument is the name of the executable file.
-- @param env Array of key=values specifying the environment strings.
-- If undefined, the new process inherits the environment of the parent process.
-- @param dir The working directory of the subprocess, or undefined
-- if the subprocess should inherit the working directory of the current process.
-- @treturn jls.lang.ProcessHandle a handle of the new process
function runtime.exec(command, env, dir)
  if type(command) == 'string' then
    command = {command}
  elseif type(command) ~= 'table' or #command < 1 then
    error('Missing command arguments')
  end
  local pb = require('jls.lang.ProcessBuilder'):new(command)
  if env then
    pb:environment(env)
  end
  if dir then
    pb:directory(dir) -- FIXME dir is a file
  end
  return pb:start()
end

--- Executes the specified command line in a separate thread.
-- @tparam string command The command-line to execute.
-- @tparam[opt] function callback an optional callback function to use in place of promise.
-- @treturn jls.lang.Promise a promise that resolves once the command has been executed.
function runtime.execute(command, callback)
  local cb, d = Promise.ensureCallback(callback)
  processLib.execute(command, cb)
  return d
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