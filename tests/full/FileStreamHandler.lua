local lu = require('luaunit')

local event = require('jls.lang.event')
local Path = require('jls.io.Path')
local FileStreamHandler = require('jls.io.streams.FileStreamHandler')
local StreamHandler = require('jls.io.streams.StreamHandler')
local BufferedStreamHandler = require('jls.io.streams.BufferedStreamHandler')

local TMP_FILENAME = Path.cleanPath('tests/test_fsh.tmp')

local function createFile(path, content)
  local file = io.open(path, 'wb')
  file:write(content) -- TODO check for errors
  file:close()
end

local function assertFileContent(path, expectedContent)
  local file = io.open(path, 'rb')
  lu.assertNotIsNil(file)
  local fileContent = file:read('a') -- TODO check for errors
  file:close()
  lu.assertEquals(fileContent, expectedContent)
end

function Test_readAll()
  local data = string.rep('1234567890', 10)
  createFile(TMP_FILENAME, data)

  local bufferedStream = BufferedStreamHandler:new(StreamHandler.null)
  local buffer = bufferedStream:getStringBuffer()

  FileStreamHandler.readAll(TMP_FILENAME, bufferedStream)
  event:loop()
  lu.assertEquals(buffer:toString(), data)

  buffer:clear()
  FileStreamHandler.readAll(TMP_FILENAME, bufferedStream, 7)
  event:loop()
  lu.assertEquals(buffer:toString(), data)
end

function Test_read()
  local data = string.rep('1234567890', 10)
  createFile(TMP_FILENAME, data)

  local bufferedStream = BufferedStreamHandler:new(StreamHandler.null)
  local buffer = bufferedStream:getStringBuffer()

  FileStreamHandler.read(TMP_FILENAME, bufferedStream, 0)
  event:loop()
  lu.assertEquals(buffer:toString(), data)

  buffer:clear()
  FileStreamHandler.read(TMP_FILENAME, bufferedStream, 0, nil, 7)
  event:loop()
  lu.assertEquals(buffer:toString(), data)

  buffer:clear()
  FileStreamHandler.read(TMP_FILENAME, bufferedStream, 0, 5, 7)
  event:loop()
  lu.assertEquals(buffer:toString(), string.sub(data, 1, 5))

  buffer:clear()
  FileStreamHandler.read(TMP_FILENAME, bufferedStream, 1, nil, 7)
  event:loop()
  lu.assertEquals(buffer:toString(), string.sub(data, 2))

  buffer:clear()
  FileStreamHandler.read(TMP_FILENAME, bufferedStream, 1, 5, 7)
  event:loop()
  lu.assertEquals(buffer:toString(), string.sub(data, 2, 6))
end

function Test_readSync()
  local data = string.rep('1234567890', 10)
  createFile(TMP_FILENAME, data)

  local bufferedStream = BufferedStreamHandler:new(StreamHandler.null)
  local buffer = bufferedStream:getStringBuffer()

  FileStreamHandler.readSync(TMP_FILENAME, bufferedStream, 0)
  lu.assertEquals(buffer:toString(), data)

  buffer:clear()
  FileStreamHandler.readSync(TMP_FILENAME, bufferedStream, 0, nil, 7)
  lu.assertEquals(buffer:toString(), data)

  buffer:clear()
  FileStreamHandler.readSync(TMP_FILENAME, bufferedStream, 0, 5, 7)
  lu.assertEquals(buffer:toString(), string.sub(data, 1, 5))

  buffer:clear()
  FileStreamHandler.readSync(TMP_FILENAME, bufferedStream, 1, nil, 7)
  lu.assertEquals(buffer:toString(), string.sub(data, 2))

  buffer:clear()
  FileStreamHandler.readSync(TMP_FILENAME, bufferedStream, 1, 5, 7)
  lu.assertEquals(buffer:toString(), string.sub(data, 2, 6))
end

function Test_z_cleanup()
  -- delete tmp file
  os.remove(TMP_FILENAME)
end

os.exit(lu.LuaUnit.run())
