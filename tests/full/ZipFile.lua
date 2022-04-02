local lu = require('luaunit')

local File = require('jls.io.File')
local ZipFile = require('jls.util.zip.ZipFile')
local logger = require('jls.lang.logger')

local TEST_PATH = 'tests/full'
local TMP_PATH = TEST_PATH..'/tmp'
local TMP_DIR = File:new(TMP_PATH)

local function setUpTmpDir()
  if TMP_DIR:isDirectory() then
    if not TMP_DIR:deleteAll() then
      error('Cannot delete tmp dir')
    end
  else
    if not TMP_DIR:mkdir() then
      error('Cannot create tmp dir')
    end
  end
end

Tests = {}

function Tests:tearDown()
  if not TMP_DIR:deleteRecursive() then
    error('Cannot delete tmp dir')
  end
end

function Tests:test_exists()
  setUpTmpDir()

  logger:info('create directories and files')
  local z = File:new(TMP_DIR, 'z')
  local a = File:new(TMP_DIR, 'a')
  a:write('Test a')
  local b = File:new(TMP_DIR, 'b')
  b:write('Test b')
  b:setLastModified(830908800000)

  logger:info('zip directories and files')
  ZipFile.zipTo(z, {a, b})

  logger:info('delete directories and files')
  a:delete()
  b:delete()
  lu.assertEquals(a:exists(), false)
  lu.assertEquals(b:exists(), false)

  logger:info('unzip directories and files')
  ZipFile.unzipTo(z, TMP_DIR)
  lu.assertEquals(a:isFile(), true)
  lu.assertEquals(b:isFile(), true)
  lu.assertEquals(b:lastModified(), 830908800000)
  lu.assertEquals(a:readAll(), 'Test a')
  lu.assertEquals(b:readAll(), 'Test b')
end

function Tests:test_Struct_to_from()
  local Struct = ZipFile._Struct

  --lu.assertEquals(res, exp)
  --lu.assertIsNil(res)
  local struct = Struct:new({
    {name = 'aUInt8', type = 'B'},
    {name = 'aInt8', type = 'b'},
    {name = 'aUInt16', type = 'H'},
    {name = 'aInt16', type = 'h'},
    {name = 'aUInt32', type = 'I4'},
    {name = 'aInt32', type = 'i4'}
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
