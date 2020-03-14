local lu = require('luaunit')

local event = require('jls.lang.event')
local system = require('jls.lang.system')
local streams = require('jls.io.streams')
local ProcessBuilder = require('jls.lang.ProcessBuilder')
local Pipe = require('jls.io.Pipe')

function test_pipe()
  local text = 'Hello world!'
  local pb = ProcessBuilder:new({ProcessBuilder.getExecutablePath(), '-e', 'print("'..text..'")'})
  --pb:environment({'A_KEY=VALUE A', 'B_KEY=VALUE B'})
  local p = Pipe.create()
  pb:redirectOutput(p)
  local ph = pb:start()
  --print('pid', ph:getPid())
  local outputData
  p:readStart(streams.CallbackStreamHandler:new(function(err, data)
    if data then
      outputData = string.gsub(data, '%s*$', '')
    else
      p:close()
    end
  end))
  event:loop()
  lu.assertEquals(outputData, text)
  lu.assertEquals(ph:isAlive(), false)
end

function test_env()
  local text = 'Hello world!'
  local pb = ProcessBuilder:new({ProcessBuilder.getExecutablePath(), '-e', 'print(os.getenv("A_KEY"))'})
  pb:environment({'A_KEY='..text, 'B_KEY=VALUE B'})
  local p = Pipe.create()
  pb:redirectOutput(p)
  local ph = pb:start()
  local outputData
  p:readStart(streams.CallbackStreamHandler:new(function(err, data)
    if data then
      outputData = string.gsub(data, '%s*$', '')
    else
      p:close()
    end
  end))
  event:loop()
  lu.assertEquals(outputData, text)
  lu.assertEquals(ph:isAlive(), false)
end

function test_exitCode()
  local code = 11
  local pb = ProcessBuilder:new({ProcessBuilder.getExecutablePath(), '-e', 'os.exit('..tostring(code)..')'})
  local exitCode
  local ph = pb:start(function(c)
    exitCode = c
  end)
  event:loop()
  lu.assertEquals(exitCode, code)
  lu.assertEquals(ph:isAlive(), false)
end

os.exit(lu.LuaUnit.run())
