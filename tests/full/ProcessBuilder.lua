local lu = require('luaunit')

-- JLS_REQUIRES=\!luv

local ProcessBuilder = require('jls.lang.ProcessBuilder')
local ProcessHandle = require('jls.lang.ProcessHandle')
local loader = require('jls.lang.loader')
local Pipe = loader.tryRequire('jls.io.Pipe')
local File = require('jls.io.File')
local FileDescriptor = require('jls.io.FileDescriptor')
local loop = require('jls.lang.loopWithTimeout')

local logger = require('jls.lang.logger')

local LUA_PATH = ProcessHandle.getExecutablePath()
logger:fine('Lua path is "%s"', LUA_PATH)
local WRITE = 'io.write'
if string.find(LUA_PATH, 'luvit$') then
  WRITE = 'print'
end

local function getNames(m)
  local names = {}
  for name, c in pairs(package.loaded) do
    if c == m then
      table.insert(names, name)
    end
  end
  return names
end
--print('ProcessHandle is '..table.concat(getNames(ProcessHandle), ','))

function Test_pipe_redirect()
  if not Pipe then
    print('/!\\ skipping pipe redirect test')
    lu.success()
  end
  local text = 'Hello world!'
  local pb = ProcessBuilder:new(LUA_PATH, '-e', WRITE..'("'..text..'")')
  local p = Pipe:new()
  pb:redirectOutput(p)
  local ph, err = pb:start()
  if not ph then
    p:close()
  end
  lu.assertNil(err)
  lu.assertNotNil(ph)
  --print('pid', ph:getPid())
  local outputData
  p:readStart(function(err, data)
    if data then
      outputData = data
    else
      p:close()
    end
  end)
  if not loop(function()
    p:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertStrContains(outputData, text)
  --lu.assertEquals(ph:isAlive(), false)
end

function Test_env()
  if not Pipe then
    print('/!\\ skipping env test')
    lu.success()
  end
  local text = 'Hello world!'
  local pb = ProcessBuilder:new({LUA_PATH, '-e', WRITE..'(os.getenv("A_KEY"))'})
  pb:environment({A_KEY = text, B_KEY = 'VALUE B'})
  local p = Pipe:new()
  pb:redirectOutput(p)
  local ph = pb:start()
  local outputData
  p:readStart(function(err, data)
    if data then
      outputData = data
    else
      p:close()
    end
  end)
  if not loop(function()
    p:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertStrContains(outputData, text)
  --lu.assertEquals(ph:isAlive(), false)
end

function Test_exit_code()
  local code = 11
  local pb = ProcessBuilder:new({LUA_PATH, '-e', 'os.exit('..code..')'})
  local exitCode
  local ph = pb:start()
  print('pid', ph:getPid())
  ph:ended():next(function(c)
    exitCode = c
  end)
  if not loop(30000) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(exitCode, code)
  if ph then
    lu.assertEquals(ph:isAlive(), false)
  end
end

function Test_destroy()
  local ms = 5000
  local pb = ProcessBuilder:new({LUA_PATH, '-lsys=jls.lang.sys', '-e', 'sys.sleep('..ms..')'})
  local t = os.time()
  local ph = pb:start()
  lu.assertEquals(ph:isAlive(), true)
  ph:ended():next(function(c)
    t = os.time() - t
  end)
  ph:destroy()
  if not loop(30000) then
    lu.fail('Timeout reached')
  end
  lu.assertTrue(t < 4)
  if ph then
    lu.assertEquals(ph:isAlive(), false)
  end
end

function Test_file_redirect()
  if not Pipe then
    print('/!\\ skipping file redirect test')
    lu.success()
  end
  local tmpFile = File:new('test.tmp')
  if tmpFile:exists() then
    tmpFile:delete()
  end
  local fd = FileDescriptor.openSync(tmpFile, 'w')
  local pb = ProcessBuilder:new({LUA_PATH, '-e', WRITE..'("Hello")'})
  pb:redirectOutput(fd)
  local ph = pb:start()
  ph:ended():next(function(c)
    -- use callback to block the event loop until process termination
  end)
  fd:close()
  if not loop(function()
    ph:destroy()
    tmpFile:delete()
  end) then
    lu.fail('Timeout reached')
  end
  local output = tmpFile:readAll()
  tmpFile:delete()
  lu.assertStrContains(output, 'Hello')
end

os.exit(lu.LuaUnit.run())
