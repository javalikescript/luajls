local lu = require('luaunit')

local FileDescriptor = require('jls.io.FileDescriptor')
local Path = require('jls.io.Path')

local TMP_FILENAME = Path.cleanPath('tests/test_fd.tmp')

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

function test_readSync_no_file()
    -- delete tmp file
    os.remove(TMP_FILENAME)

    local fd = FileDescriptor.openSync(TMP_FILENAME, 'r')
    if fd then
        fd:closeSync() -- just in case
    end
    lu.assertIsNil(fd)
end

function test_readSync()
    -- prepare tmp file with some content
    createFile(TMP_FILENAME, '12345678901234567890Some Content')

    local fd = FileDescriptor.openSync(TMP_FILENAME, 'r')
    local content
    content = fd:readSync(20)
    lu.assertEquals(content, '12345678901234567890')
    content = fd:readSync(2048)
    lu.assertEquals(content, 'Some Content')
    content = fd:readSync(2048)
    lu.assertEquals(content, nil)
    fd:closeSync()

    -- delete tmp file
    os.remove(TMP_FILENAME)
end

function test_writeSync()
    local err
    local fd = FileDescriptor.openSync(TMP_FILENAME, 'w')
    _, err = fd:writeSync('12345678901234567890')
    lu.assertIsNil(err)
    _, err = fd:writeSync('Some Content')
    lu.assertIsNil(err)
    fd:flushSync()
    fd:closeSync()

    assertFileContent(TMP_FILENAME, '12345678901234567890Some Content')

    -- delete tmp file
    os.remove(TMP_FILENAME)
end

os.exit(lu.LuaUnit.run())
