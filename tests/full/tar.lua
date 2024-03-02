local lu = require('luaunit')

local tar = require('jls.util.zip.tar')
local File = require('jls.io.File')
local Codec = require('jls.util.Codec')
local StreamHandler = require('jls.io.StreamHandler')
local base64 = Codec.getInstance('base64')

local TEST_PATH = 'tests/full'
local TMP_PATH = TEST_PATH..'/tmp'
local TMP_DIR = File:new(TMP_PATH)

-- echo -n Hi>a.txt; echo "Hello World !">b.txt; tar -czf - a.txt b.txt | base64
local SAMPLE_TAR_GZ = base64:decode('H4sIAAAAAAAAA+3TMQrCQBCF4a09xXgB2TGb7BVyA+sVUwRWAskGPL5JsBBExCJZhf9rBmameM0Lh3RLZl12Ujk3T/WlfZ4PR6PFtCkL7+Y/VWfViF0512IcUuhFzBCuYxPf/326/6m6zZ0AOZ1/of9avfbf0/8t1E2MnZy6Pl5kv8udBgAAAAAAAAAAAAAAAN+6A+eyywsAKAAA')

Tests = {}

function Tests:setUp()
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

function Tests:tearDown()
  if not TMP_DIR:deleteRecursive() then
    error('Cannot delete tmp dir')
  end
end

local function verifyExtraction(invert)
  local aFile = File:new(TMP_DIR, 'a.txt')
  if invert then
    lu.assertFalse(aFile:isFile())
    return
  end
  local bFile = File:new(TMP_DIR, 'b.txt')
  lu.assertTrue(aFile:isFile())
  lu.assertTrue(bFile:isFile())
  lu.assertEquals(aFile:readAll(), 'Hi')
  lu.assertEquals(bFile:readAll(), 'Hello World !\n')
end

function Tests:test_extractStreamTo()
  verifyExtraction(true)
  local sh = tar.extractStreamTo(TMP_DIR, true)
  StreamHandler.fill(sh, SAMPLE_TAR_GZ)
  verifyExtraction()
end

function Tests:test_extractFileTo()
  local tarFile = File:new(TMP_DIR, 'test.tar.gz')
  tarFile:write(SAMPLE_TAR_GZ)
  verifyExtraction(true)
  tar.extractFileTo(tarFile, TMP_DIR)
  verifyExtraction()
end

os.exit(lu.LuaUnit.run())
