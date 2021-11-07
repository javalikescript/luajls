--- Provides interaction with the underlying OS runtime.
-- @module jls.lang.runtime

local loader = require('jls.lang.loader')

local runtime = {}

local isWindowsOS = string.sub(package.config, 1, 1) == '\\' or string.find(package.cpath, '%.dll')

-- Returns the command line corresponding to the specified arguments.
-- @tparam table args Array of strings specifying the command-line arguments.
-- @treturn string the command line
function runtime.formatCommandLine(args)
  local pargs = {}
  for _, arg in ipairs(args) do
    local earg = arg
    if isWindowsOS then
      -- see https://ss64.com/nt/syntax-esc.html
      if string.find(arg, '[%s"&\\<>%^|%%]') and not string.match(arg, '^[<>|&]+$') then
        earg = '"'..string.gsub(arg, '"', '""')..'"'
      end
    else
      -- see https://www.oreilly.com/library/view/learning-the-bash/1565923472/ch01s09.html
      if string.find(arg, '[%s"~`#$&%*%(%)\\|%[%]{};\'"<>/%?!]') and not string.match(arg, '^[<>|&]+$') then
        earg = '"'..string.gsub(arg, '["\\]', '\\%&1')..'"'
      end
    end
    table.insert(pargs, earg)
  end
  if isWindowsOS then
    return '"'..table.concat(pargs, ' ')..'"'
  end
  return table.concat(pargs, ' ')
end

runtime.exec = loader.lazyFunction(function(ProcessBuilder)
  --- Executes the specified command and arguments in a separate process with the specified environment and working directory.
  -- @param command Array of strings specifying the command-line arguments.
  -- The first argument is the name of the executable file.
  -- @param env Array of key=values specifying the environment strings.
  -- If undefined, the new process inherits the environment of the parent process.
  -- @param dir The working directory of the subprocess, or undefined
  -- if the subprocess should inherit the working directory of the current process.
  -- @treturn jls.lang.ProcessHandle a handle of the new process
  runtime.exec = function(command, env, dir)
    if type(command) == 'string' then
      command = {command}
    elseif type(command) ~= 'table' or #command < 1 then
      error('Missing command arguments')
    end
    local pb = ProcessBuilder:new(command)
    if env then
      pb:environment(env)
    end
    if dir then
      pb:directory(dir) -- FIXME dir is a file
    end
    return pb:start()
  end
  return runtime.exec
end, 'jls.lang.ProcessBuilder')

local function applyExecuteCallback(cb, anyCode, status, kind, code)
  if anyCode then
    cb(nil, {
      code = math.floor(code),
      kind = kind
    })
  elseif status then
    cb()
  else
    cb('Execute fails with '..tostring(kind)..' code '..tostring(code))
  end
end

runtime.execute = loader.lazyFunction(function(Promise, Thread)
  --- Executes the specified command line in a separate thread.
  -- The promise will be rejected if the process exit code is not zero.
  -- The error is a table with a code and a kind fields.
  -- @tparam string command The command-line to execute.
  -- @tparam[opt] boolean anyCode true to resolve the promise with any exit code.
  -- @tparam[opt] function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the command has been executed.
  runtime.execute = function(command, anyCode, callback)
    if type(anyCode) == 'function' then
      callback = anyCode
      anyCode = false
    end
    local cb, d = Promise.ensureCallback(callback)
    if Thread then
      Thread:new(function(cmd)
        -- Windows uses 32-bit unsigned integers as exit codes
        -- windows system function does not return the exit code but the errno
        local status, kind, code = os.execute(cmd)
        -- status is a shorter for kind == 'exit' and code == 0
        return tostring(status)..' '..kind..' '..tostring(code)
      end):start(command):ended():next(function(result)
        local status, kind, code = string.match(result, '^(%a+) (%a+) %-?(%d+)$')
        applyExecuteCallback(cb, anyCode, status == 'true', kind, tonumber(code))
      end, function(reason)
        cb(reason or 'Unkown error')
      end)
    else
      applyExecuteCallback(cb, anyCode, os.execute(command))
    end
    return d
  end
  return runtime.execute
end, 'jls.lang.Promise', 'jls.lang.Thread')

local shutdownHooks = {}

local function runShutdownHooks()
  local list = shutdownHooks
  shutdownHooks = {}
  for _, fn in ipairs(list) do
    fn()
  end
end

-- Registers a function that will be called prior Lua termination.
function runtime.addShutdownHook(fn)
  if type(JLS_RUNTIME_GLOBAL_OBJECT) == 'nil' then
    -- registering a global object to check if the event loop has been called and processed all the events.
    JLS_RUNTIME_GLOBAL_OBJECT = setmetatable({}, {
      __gc = runShutdownHooks
    })
  end
  table.insert(shutdownHooks, fn)
end

--- Terminates the program and returns a value to the OS.
-- @param code The exit code to return to the OS.
function runtime.exit(code)
  runShutdownHooks()
  return os.exit(code, true)
end

--- Runs the garbage collector.
function runtime.gc()
  collectgarbage('collect')
end

--- Forcibly terminates the program and returns a value to the OS.
-- @param code The exit code to return to the OS.
function runtime.halt(code)
  runShutdownHooks()
  return os.exit(code, false)
end

return runtime