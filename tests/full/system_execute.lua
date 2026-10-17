local lu = require('luaunit')

local system = require('jls.lang.system')
local ProcessHandle = require('jls.lang.ProcessHandle')
local loop = require('jls.lang.loopWithTimeout')

local LUA_EXE_PATH = ProcessHandle.getExecutablePath()

local function commandArgs(code)
  return {LUA_EXE_PATH, '-e', 'os.exit('..tostring(code)..')'}
end

local function commandLine(code)
  return system.formatCommandLine(commandArgs(code))
end

function Test_execute_success()
  local success = false
  system.execute(commandLine(0)):next(function()
    success = true
  end)
  if not loop() then
    lu.fail('Timeout reached')
  end
  lu.assertTrue(success)
end

function Test_execute_failure()
  local failure = false
  local failureReason = nil
  system.execute(commandLine(1)):catch(function(reason)
    failureReason = reason
    failure = true
  end)
  if not loop() then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(failureReason, 'Execute fails with exit code 1')
  lu.assertTrue(failure)
end

local function assertExitCode(code)
  local exitCode = nil
  system.execute(commandLine(code), true):next(function(info)
    exitCode = info.code
  end)
  if not loop() then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(exitCode, code)
end

function Test_execute_with_exitCode()
  assertExitCode(0)
  assertExitCode(11)
end

function Test_findExecutablePath()
  lu.assertNil(system.findExecutablePath('unlikely-executable-name'))
  local executableName = system.isWindows() and 'cmd' or 'sh'
  local executablePath = system.findExecutablePath(executableName)
  --print(executableName, executablePath)
  lu.assertNotNil(executablePath)
end

function Test_exec()
  local ph = system.exec(commandArgs(0))
  lu.assertTrue(ph:isAlive())
  if not loop() then
    lu.fail('Timeout reached')
  end
  lu.assertFalse(ph:isAlive())
end

function Test_getArguments()
  lu.assertEquals(type(system.getArguments()), 'table')
  lu.assertEquals(type(system.getLibraryExtension()), 'string')
end

local function unquoteCommandLine(line)
  if system.isWindows() then
    -- on Windows the whole command line is enclosed in double quotes
    return string.sub(line, 2, -2)
  end
  return line
end

local function formatCommandLinePosix(args)
  -- reevaluate the module with a POSIX like package config
  local savedConfig = package.config
  local savedModule = package.loaded['jls.lang.formatCommandLine']
  package.config = '/\n;\n?\n!\n-\n'
  package.loaded['jls.lang.formatCommandLine'] = nil
  local formatCommandLine = require('jls.lang.formatCommandLine')
  package.config = savedConfig
  package.loaded['jls.lang.formatCommandLine'] = savedModule
  return formatCommandLine(args)
end

function Test_formatCommandLine()
  -- arguments without special characters are not quoted
  lu.assertEquals(unquoteCommandLine(system.formatCommandLine({'lua', '-e'})), 'lua -e')
  -- an argument with a space is enclosed in double quotes
  lu.assertEquals(unquoteCommandLine(system.formatCommandLine({'a b'})), '"a b"')
end

function Test_formatCommandLine_escaping()
  -- the escaping rules depend on the platform
  if system.isWindows() then
    lu.assertEquals(unquoteCommandLine(system.formatCommandLine({'x"y'})), '"x""y"')
    lu.assertEquals(unquoteCommandLine(system.formatCommandLine({'x\\y'})), '"x\\y"')
  else
    lu.assertEquals(unquoteCommandLine(system.formatCommandLine({'x"y'})), '"x\\"y"')
    lu.assertEquals(unquoteCommandLine(system.formatCommandLine({'x\\y'})), '"x\\\\y"')
  end
end

function Test_formatCommandLine_posix()
  -- on POSIX the double quote and the backslash are escaped with a backslash
  lu.assertEquals(formatCommandLinePosix({'lua', '-e'}), 'lua -e')
  lu.assertEquals(formatCommandLinePosix({'a b'}), '"a b"')
  lu.assertEquals(formatCommandLinePosix({'x"y'}), '"x\\"y"')
  lu.assertEquals(formatCommandLinePosix({'x\\y'}), '"x\\\\y"')
end

function Test_gc()
  local flag = false
  local t = setmetatable({}, {
    __gc = function()
      flag = true
    end
  })
  lu.assertFalse(flag)
  t = nil
  system.gc()
  lu.assertTrue(flag)
end

os.exit(lu.LuaUnit.run())
