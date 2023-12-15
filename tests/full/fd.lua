local lu = require('luaunit')

-- JLS_LOGGER_LEVEL=finer
-- JLS_REQUIRES=\!luv

local FileDescriptor = require('jls.io.FileDescriptor')
local File = require('jls.io.File')
local Promise = require('jls.lang.Promise')
local loop = require('jls.lang.loopWithTimeout')

function Test_openSync_r()
  local fd, err = FileDescriptor.openSync('tests/does_not_exist', 'r')
  lu.assertNil(fd)
  lu.assertNotNil(err)
  fd, err = FileDescriptor.openSync('tests/full/fd.lua', 'r')
  if fd then
    fd:closeSync()
  end
  lu.assertNotNil(fd)
  lu.assertNil(err)
end

local TMP_FILENAME = 'tests/to_remove.tmp'
local TMP_FILE = File:new(TMP_FILENAME)

function Test_openSync_w()
  local fd, err = FileDescriptor.openSync('tests/does_not_exist/to_remove.tmp', 'w')
  lu.assertNil(fd)
  lu.assertNotNil(err)
  fd, err = FileDescriptor.openSync(TMP_FILENAME, 'w')
  if fd then
    fd:closeSync()
  end
  TMP_FILE:delete()
  lu.assertNotNil(fd)
  lu.assertNil(err)
end

function Test_writeSync()
  local part1, part2 = 'Hello', ' world!'
  local fd = FileDescriptor.openSync(TMP_FILENAME, 'w')
  lu.assertNotNil(fd)
  fd:writeSync(part1)
  fd:writeSync(part2)
  fd:closeSync()
  local content = TMP_FILE:readAll()
  TMP_FILE:delete()
  lu.assertEquals(content, part1..part2)
end

function Test_readSync()
  local part1, part2 = 'Hello', ' world!'
  TMP_FILE:write(part1..part2)
  local fd = FileDescriptor.openSync(TMP_FILENAME, 'r')
  lu.assertNotNil(fd)
  local data1 = fd:readSync(#part1)
  local data2 = fd:readSync(1024)
  local data3 = fd:readSync(1024)
  fd:closeSync()
  TMP_FILE:delete()
  lu.assertEquals(data1, part1)
  lu.assertEquals(data2, part2)
  lu.assertNil(data3)
end

function Test_read()
  local part1, part2 = 'Hello', ' world!'
  local data1, data2, data3
  local errors = {}
  TMP_FILE:write(part1..part2)
  local fd = FileDescriptor.openSync(TMP_FILENAME, 'r')
  lu.assertNotNil(fd)
  fd:read(#part1, function(err, d)
    table.insert(errors, err)
    data1 = d
  end)
  fd:read(1024, function(err, d)
    table.insert(errors, err)
    data2 = d
  end)
  fd:read(1024, function(err, d)
    table.insert(errors, err)
    data3 = d
  end)
  --require('jls.lang.event'):loop()
  loop()
  fd:closeSync()
  TMP_FILE:delete()
  lu.assertEquals(errors, {})
  lu.assertEquals(data1, part1)
  lu.assertEquals(data2, part2)
  lu.assertNil(data3)
end

function Test_read_async()
  if _VERSION == 'Lua 5.1' then
    print('/!\\ skipping test due to Lua version')
    lu.success()
    return
  end
  local part1, part2 = 'Hello', ' world!'
  local data1, data2, data3
  TMP_FILE:write(part1..part2)
  local fd = FileDescriptor.openSync(TMP_FILENAME, 'r')
  lu.assertNotNil(fd)
  Promise.async(function(await)
    data1 = await(fd:read(#part1))
    data2 = await(fd:read(1024))
    data3 = await(fd:read(1024))
  end):catch(function(reason)
    print(reason)
  end)
  --require('jls.lang.event'):loop()
  loop()
  fd:closeSync()
  TMP_FILE:delete()
  lu.assertEquals(data1, part1)
  lu.assertEquals(data2, part2)
  lu.assertNil(data3)
end

os.exit(lu.LuaUnit.run())
