local lu = require('luaunit')

local system = require('jls.lang.system')
local loop = require('jls.lang.loopWithTimeout')

local LUA_EXE_PATH = require('jls.lang.ProcessBuilder').getExecutablePath()

local function commandLine(code)
  return system.formatCommandLine({
    LUA_EXE_PATH,
    '-e',
    'os.exit('..tostring(code)..')'
  })
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

os.exit(lu.LuaUnit.run())
