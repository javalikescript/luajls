local lu = require('luaunit')

local runtime = require('jls.lang.runtime')
local loop = require('jls.lang.loader').load('loop', 'tests', false, true)

local LUA_EXE_PATH = require('jls.lang.ProcessBuilder').getExecutablePath()

function Test_execute()
  local exitCode = nil
  local line = table.concat({
    LUA_EXE_PATH,
    '-e',
    '"os.exit(0)"'
  }, ' ')
  runtime.execute(line):next(function()
    exitCode = 0
  end, function(err)
    exitCode = err and err.code
  end)
  if not loop() then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(exitCode, 0)
end

function Test_execute_with_exitCode()
  local code = 11
  local exitCode = nil
  local line = table.concat({
    LUA_EXE_PATH,
    '-e',
    '"os.exit('..tostring(code)..')"'
  }, ' ')
  runtime.execute(line):next(function()
    exitCode = 0
  end, function(err)
    exitCode = err and err.code
  end)
  if not loop() then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(exitCode, code)
end

os.exit(lu.LuaUnit.run())
