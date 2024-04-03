local lu = require('luaunit')

local ProcessBuilder = require('jls.lang.ProcessBuilder')
local ProcessHandle = require('jls.lang.ProcessHandle')
local system = require('jls.lang.system')
local File = require('jls.io.File')
local loop = require('jls.lang.loopWithTimeout')

local TEST_FILENAME = 'examples/README.md'
local TMP_FILENAME = 'tests/to_remove.tmp'
local TMP_2_FILENAME = 'tests/to_remove_2.tmp'
local TEST_PORT = 8765
local LUA_PATH = ProcessHandle.getExecutablePath()

local function assertExitCode(ph, value, message)
  local exitCode
  ph:ended():next(function(c)
    exitCode = c
  end)
  if not loop(15000) then
    ph:destroy()
    lu.fail('Timeout reached')
  end
  lu.assertEquals(exitCode, value or 0, message)
end

local function assertFileEquals(file, expectedFile, message)
  lu.assertEquals(File.asFile(file):readAll(), File.asFile(expectedFile):readAll(), message)
end

local function deleteFiles(...)
  for _, file in ipairs({...}) do
    File.asFile(file):delete()
  end
end

local function exec(command, expectedExitCode, redirect)
  local pb = ProcessBuilder:new(command)
  if redirect then
    pb:setRedirectOutput(system.output)
    pb:setRedirectError(system.error)
  end
  local ph = pb:start()
  if expectedExitCode then
    assertExitCode(ph, expectedExitCode, table.concat(command, ' '))
  else
    return ph
  end
end

local function findCodeBlock(s, at)
  local _, i = string.find(s, '```%s*lua\r?\n', at)
  if i then
    local j = string.find(s, '```\r?\n', i)
    if j then
      return string.sub(s, i + 1, j - 1), i + 1, j
    end
  end
end

local loadstr = loadstring or load

local function loadCodeBlocks(mdFilename)
  local mdFile = File:new(mdFilename)
  if not mdFile:exists() then
    lu.fail('File not found '..tostring(mdFilename))
  end
  local mdContent = mdFile:readAll()
  local offset = 1
  while true do
    local code
    code, offset = findCodeBlock(mdContent, offset)
    if not code then
      break
    end
    local fn, err = loadstr(code, mdFilename, 't')
    if not fn then
      lu.fail('Error while loading '..tostring(mdFilename)..' due to '..tostring(err))
    end
  end
end

function Test_markdown()
  loadCodeBlocks('README.md')
  loadCodeBlocks('doc_topics/manual.md')
end

local isLuv = package.loaded['jls.lang.event'] == package.loaded['jls.lang.event-luv']

function Test_help()
  if not isLuv then
    print('/!\\ skipping default test')
    lu.success()
    return
  end
  for _, name in ipairs({'browser.lua', 'cipher.lua', 'discover.lua', 'httpClient.lua', 'httpProxy.lua', 'mqtt.lua', 'webServer.lua', 'wsClient.lua', 'zip.lua'}) do
    exec({LUA_PATH, 'examples/'..name, '--help'}, 0)
  end
end

function Test_cipher()
  exec({LUA_PATH, 'examples/cipher.lua', '-e', '--file', TEST_FILENAME, '--out', TMP_FILENAME, '--overwrite'}, 0)
  exec({LUA_PATH, 'examples/cipher.lua', '-d', '--file', TMP_FILENAME, '--out', TMP_2_FILENAME, '--overwrite'}, 0)
  assertFileEquals(TEST_FILENAME, TMP_2_FILENAME)
  deleteFiles(TMP_FILENAME, TMP_2_FILENAME)
end

function Test_httpClient_webServer()
  if _VERSION == 'Lua 5.1' then
    print('/!\\ skipping test due to Lua version')
    lu.success()
    return
  end
  local redirect = false
  local phServer = exec({LUA_PATH, 'examples/webServer.lua', '--port', tostring(TEST_PORT)}, nil, redirect)
  system.sleep(500) -- let server starts
  local phClient = exec({LUA_PATH, 'examples/httpClient.lua', '--url', string.format('http://localhost:%d/%s', TEST_PORT, TEST_FILENAME), '--out.file', TMP_FILENAME, '--out.overwrite'}, nil, redirect)
  phClient:ended():finally(function()
    --print('closing server')
    phServer:destroy()
  end)
  if not loop(15000) then
    phServer:destroy()
    phClient:destroy()
    lu.fail('Timeout reached')
  end
  assertFileEquals(TMP_FILENAME, TEST_FILENAME)
  deleteFiles(TMP_FILENAME)
end

os.exit(lu.LuaUnit.run())
