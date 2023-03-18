local lu = require('luaunit')

local ProcessBuilder = require('jls.lang.ProcessBuilder')
local system = require('jls.lang.system')
local File = require('jls.io.File')
local loop = require('jls.lang.loopWithTimeout')

local logger = require('jls.lang.logger')

local LUA_PATH = ProcessBuilder.getExecutablePath()
logger:fine('Lua path is "'..tostring(LUA_PATH)..'"')

local function assertExitCode(ph, value, message)
  local exitCode
  ph:ended():next(function(c)
    exitCode = c
  end)
  if not loop(30000) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(exitCode, value or 0, message)
end

local function assertFileEquals(file1, file2, message)
  lu.assertEquals(File.asFile(file1):readAll(), File.asFile(file2):readAll(), message)
end

local function deleteFiles(...)
  for _, file in ipairs({...}) do
    File.asFile(file):delete()
  end
end

local function exec(command, expectedExitCode)
  local pb = ProcessBuilder:new(command)
  --pb:setRedirectOutput(system.output)
  --pb:setRedirectError(system.error)
  local ph = pb:start()
  if expectedExitCode then
    assertExitCode(ph, expectedExitCode, table.concat(command, ' '))
  else
    return ph
  end
end

function Test_help()
  for _, name in ipairs({'browser.lua', 'cipher.lua', 'httpClient.lua', 'httpProxy.lua', 'mqtt.lua', 'package.lua', 'ssdp.lua', 'webServer.lua', 'wsClient.lua', 'zip.lua'}) do
    exec({LUA_PATH, 'examples/'..name, '--help'}, 0)
  end
end

local TEST_FILENAME = 'examples/README.md'
local TMP_FILENAME = 'tests/to_remove.tmp'
local TMP_2_FILENAME = 'tests/to_remove_2.tmp'
local TEST_PORT = 8765

function Test_cipher()
  exec({LUA_PATH, 'examples/cipher.lua', '-e', '--file', TEST_FILENAME, '--out', TMP_FILENAME, '--overwrite'}, 0)
  exec({LUA_PATH, 'examples/cipher.lua', '-d', '--file', TMP_FILENAME, '--out', TMP_2_FILENAME, '--overwrite'}, 0)
  assertFileEquals(TEST_FILENAME, TMP_2_FILENAME)
  deleteFiles(TMP_FILENAME, TMP_2_FILENAME)
end

function Test_httpClient_webServer()
  local phServer = system.exec({LUA_PATH, 'examples/webServer.lua', '--port', tostring(TEST_PORT)})
  local phClient = system.exec({LUA_PATH, 'examples/httpClient.lua', '--url', string.format('http://localhost:%d/%s', TEST_PORT, TEST_FILENAME), '--out.file', TMP_FILENAME, '--out.overwrite'})
  phClient:ended():finally(function()
    --print('closing server')
    phServer:destroy()
  end)
  if not loop(30000) then
    lu.fail('Timeout reached')
  end
  assertFileEquals(TEST_FILENAME, TMP_FILENAME)
  deleteFiles(TMP_FILENAME)
end

os.exit(lu.LuaUnit.run())
