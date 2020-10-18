local lu = require('luaunit')

local File = require('jls.io.File')

local TEST_PATH = 'tests/full'
local TMP_PATH = TEST_PATH..'/tmp'

function Test_exists()
    local f
    f = File:new('does_not_exist')
    lu.assertEquals(f:exists(), false)
    f = File:new('.')
    lu.assertEquals(f:exists(), true)
end

function Test_isFile()
    local f
    f = File:new('does_not_exist')
    lu.assertEquals(f:isFile(), false)
    f = File:new('.')
    lu.assertEquals(f:isFile(), false)
    f = File:new(TEST_PATH..'/File.lua')
    lu.assertEquals(f:isFile(), true)
end

function Test_isDirectory()
    local f
    f = File:new('does_not_exist')
    lu.assertEquals(f:isDirectory(), false)
    f = File:new('.')
    lu.assertEquals(f:isDirectory(), true)
end

local function getTmpDir()
    local tmpDir = File:new(TMP_PATH)
    if tmpDir:isDirectory() then
        if not tmpDir:deleteRecursive() then
            error('Cannot delete tmp dir')
        end
    end
    return tmpDir
end

local function getEmptyTmpDir()
    local tmpDir = File:new(TMP_PATH)
    if tmpDir:isDirectory() then
        if not tmpDir:deleteAll() then
            error('Cannot delete tmp dir')
        end
    else
        if not tmpDir:mkdir() then
            error('Cannot create tmp dir')
        end
    end
    return tmpDir
end

function Test_mkdirs()
    local tmpDir = getEmptyTmpDir()
    local f
    f = File:new(tmpDir, 'a/b')
    lu.assertEquals(f:isDirectory(), false)
    lu.assertEquals(f:mkdirs(), true)
    lu.assertEquals(f:isDirectory(), true)
end

function Test_z_mkdir()
    local f = getTmpDir()
    lu.assertEquals(f:isDirectory(), false)
    lu.assertEquals(f:mkdir(), true)
    lu.assertEquals(f:isDirectory(), true)
    lu.assertEquals(f:delete(), true)
end

os.exit(lu.LuaUnit.run())
