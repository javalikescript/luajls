local lu = require('luaunit')

local File = require('jls.io.File')
local ZipFile = require('jls.util.zip.ZipFile')
local base64 = require('jls.util.base64')

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
  local tmpDir = getEmptyTmpDir()
  local z = File:new(tmpDir, 'z')
  local a = File:new(tmpDir, 'a')
  a:write('Test a')
  local b = File:new(tmpDir, 'b')
  b:write('Test b')
  b:setLastModified(830908800000)
  ZipFile.zipTo(z, {a, b})

  a:delete()
  b:delete()
  lu.assertEquals(a:exists(), false)
  lu.assertEquals(b:exists(), false)

  ZipFile.unzipTo(z, tmpDir)
  lu.assertEquals(a:isFile(), true)
  lu.assertEquals(b:isFile(), true)
  lu.assertEquals(b:lastModified(), 830908800000)
  lu.assertEquals(a:readAll(), 'Test a')
  lu.assertEquals(b:readAll(), 'Test b')

  getTmpDir() -- clean up
end

function Test_Struct_to_from()
  local Struct = ZipFile._Struct

  --lu.assertEquals(res, exp)
  --lu.assertIsNil(res)
  local struct = Struct:new({
    {name = 'aUInt8', type = 'UnsignedByte'},
    {name = 'aInt8', type = 'SignedByte'},
    {name = 'aUInt16', type = 'UnsignedShort'},
    {name = 'aInt16', type = 'SignedShort'},
    {name = 'aUInt32', type = 'UnsignedInt'},
    {name = 'aInt32', type = 'SignedInt'}
  })
  local t = {
    aUInt8 = 1,
    aInt8 = 2,
    aUInt16 = 3,
    aInt16 = 4,
    aUInt32 = 5,
    aInt32 = 6
  }
  lu.assertEquals(struct:fromString(struct:toString(t)), t)
end

os.exit(lu.LuaUnit.run())
