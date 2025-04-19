local lu = require('luaunit')

local File = require('jls.io.File')

local TEST_PATH = 'tests/full'
local TMP_PATH = TEST_PATH..'/tmp'

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

function Test_exists()
  local f
  f = File:new('does_not_exist')
  lu.assertFalse(f:exists())
  f = File:new('.')
  lu.assertTrue(f:exists())
end

function Test_isFile()
  local f
  f = File:new('does_not_exist')
  lu.assertFalse(f:isFile())
  f = File:new('.')
  lu.assertFalse(f:isFile())
  f = File:new(TEST_PATH..'/File.lua')
  lu.assertTrue(f:isFile())
end

function Test_isDirectory()
  local f
  f = File:new('does_not_exist')
  lu.assertFalse(f:isDirectory())
  f = File:new('.')
  lu.assertTrue(f:isDirectory())
end

function Test_mkdir()
  local tmpDir = getEmptyTmpDir()
  local f = File:new(tmpDir, 'a/b')
  lu.assertFalse(f:isDirectory())
  lu.assertNotTrue(f:mkdir())
  lu.assertFalse(f:isDirectory())
  lu.assertTrue(File:new(tmpDir, 'a'):mkdir())
  lu.assertTrue(f:mkdir())
  lu.assertTrue(f:isDirectory())
end

function Test_mkdirs()
  local tmpDir = getEmptyTmpDir()
  local f = File:new(tmpDir, 'a/b')
  lu.assertFalse(f:isDirectory())
  lu.assertTrue(f:mkdirs())
  lu.assertTrue(f:isDirectory())
end

function Test_delete()
  local tmpDir = getEmptyTmpDir()
  local f = File:new(tmpDir, 'file.tmp')
  lu.assertFalse(f:exists())
  lu.assertTrue(f:delete())
  f:write('Some data')
  lu.assertTrue(f:exists())
  lu.assertTrue(f:delete())
  lu.assertFalse(f:exists())
  local h = File:new(tmpDir, 'a')
  local i = File:new(h, 'b')
  lu.assertTrue(i:mkdirs())
  lu.assertNotTrue(h:delete())
end

function Test_write_readAll()
  local tmpDir = getEmptyTmpDir()
  local f = File:new(tmpDir, 'file.tmp')
  local d = 'Some data'
  f:write(d)
  lu.assertEquals(assert(f:readAll()), d)
  lu.assertEquals(f:length(), #d)
end

function Test_renameTo()
  local tmpDir = getEmptyTmpDir()
  local f = File:new(tmpDir, 'file.tmp')
  local d = 'Some data'
  f:write(d)
  local g = File:new(tmpDir, 'new_file.tmp')
  local h = File:new(tmpDir, 'a/b')
  lu.assertTrue(h:mkdirs())
  lu.assertNotTrue(f:renameTo(h))
  lu.assertNotTrue(g:renameTo(f))
  lu.assertTrue(f:renameTo(g))
  lu.assertFalse(f:exists())
  lu.assertEquals(g:readAll(), d)
end

function Test_copyTo()
  local tmpDir = getEmptyTmpDir()
  local f = File:new(tmpDir, 'file.tmp')
  local d = 'Some data'
  f:write(d)
  local g = File:new(tmpDir, 'new_file.tmp')
  f:copyTo(g)
  lu.assertEquals(f:readAll(), d)
  lu.assertEquals(g:readAll(), d)
end

-- last test will cleanup the tmp dir
function Test_z_mkdir()
  local f = getTmpDir()
  lu.assertFalse(f:isDirectory())
  lu.assertTrue(f:mkdir())
  lu.assertTrue(f:isDirectory())
  lu.assertTrue(f:delete())
end

os.exit(lu.LuaUnit.run())
