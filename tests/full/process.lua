local lu = require('luaunit')

local ProcessBuilder = require('jls.lang.ProcessBuilder')
local Pipe = require('jls.lang.loader').tryRequire('jls.io.Pipe')
local loop = require('jls.lang.loopWithTimeout')

local logger = require('jls.lang.logger')

local LUA_PATH = ProcessBuilder.getExecutablePath()
logger:fine('Lua path is "'..tostring(LUA_PATH)..'"')

function Test_pipe()
  --lu.runOnlyIf(Pipe)
  if not Pipe then
    lu.success()
  end
  local text = 'Hello world!'
  local pb = ProcessBuilder:new(LUA_PATH, '-e', 'print("'..text..'")')
  --pb:environment({'A_KEY=VALUE A', 'B_KEY=VALUE B'})
  local p = Pipe:new()
  pb:redirectOutput(p)
  local ph = pb:start()
  --print('pid', ph:getPid())
  local outputData
  p:readStart(function(err, data)
    if data then
      outputData = string.gsub(data, '%s*$', '')
    else
      p:close()
    end
  end)
  if not loop(function()
    p:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(outputData, text)
  lu.assertEquals(ph:isAlive(), false)
end

function Test_env()
  if not Pipe then
    lu.success()
  end
  local text = 'Hello world!'
  local pb = ProcessBuilder:new({LUA_PATH, '-e', 'print(os.getenv("A_KEY"))'})
  pb:environment({'A_KEY='..text, 'B_KEY=VALUE B'})
  local p = Pipe:new()
  pb:redirectOutput(p)
  local ph = pb:start()
  local outputData
  p:readStart(function(err, data)
    if data then
      outputData = string.gsub(data, '%s*$', '')
    else
      p:close()
    end
  end)
  if not loop(function()
    p:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(outputData, text)
  lu.assertEquals(ph:isAlive(), false)
end

function Test_exitCode()
  local code = 11
  local pb = ProcessBuilder:new({LUA_PATH, '-e', 'os.exit('..tostring(code)..')'})
  local exitCode
  local ph = pb:start(function(c)
    exitCode = c
  end)
  if not loop() then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(exitCode, code)
  if ph then
    lu.assertEquals(ph:isAlive(), false)
  end
end

os.exit(lu.LuaUnit.run())
