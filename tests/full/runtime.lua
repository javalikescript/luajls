local lu = require('luaunit')

local event = require('jls.lang.event')
local runtime = require('jls.lang.runtime')

local LUA_EXE_PATH = require('jls.lang.ProcessBuilder').getExecutablePath()

function test_execute()
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
  event:loop()
  lu.assertEquals(exitCode, 0)
end

function test_execute_with_exitCode()
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
  event:loop()
  lu.assertEquals(exitCode, code)
end

os.exit(lu.LuaUnit.run())
