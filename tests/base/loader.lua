local lu = require('luaunit')

local loader = require('jls.lang.loader')

local TEST_MODULE_NAME = 'mod_test'
local TEST_2_MODULE_NAME = 'mod_test_2'
local UNKNOWN_MODULE_NAME = 'not_mod_test'

TestLoader = {}

function TestLoader:setUp()
  loader.appendLuaPath('tests/?.lua')
  loader.unload(TEST_MODULE_NAME)
  loader.unload(TEST_2_MODULE_NAME)
end

function TestLoader:tearDown()
  loader.resetLuaPath()
end

function TestLoader:test_tryRequire()
  lu.assertNil(loader.tryRequire(UNKNOWN_MODULE_NAME))
  local m = loader.tryRequire(TEST_MODULE_NAME)
  lu.assertNotNil(m)
  lu.assertEquals(m.c, 'Hi')
end

function TestLoader:test_getRequired()
  lu.assertNil(loader.getRequired(TEST_MODULE_NAME))
  local mr = require(TEST_MODULE_NAME)
  local m = loader.getRequired(TEST_MODULE_NAME)
  lu.assertNotNil(m)
  lu.assertIs(m, mr)
end

function TestLoader:test_requireOne_first()
  local m = loader.requireOne(TEST_MODULE_NAME, UNKNOWN_MODULE_NAME, TEST_2_MODULE_NAME)
  lu.assertNotNil(m)
  lu.assertIs(m, require(TEST_MODULE_NAME))
end

function TestLoader:test_requireOne_last_loaded()
  local mr = require(TEST_2_MODULE_NAME)
  local m = loader.requireOne(UNKNOWN_MODULE_NAME, TEST_MODULE_NAME, TEST_2_MODULE_NAME)
  lu.assertNotNil(m)
  lu.assertIs(m, mr)
end

function TestLoader:test_requireByPath()
  local v = loader.requireByPath(TEST_MODULE_NAME..'.c')
  lu.assertIs(v, 'Hi')
  lu.assertNotNil(loader.getRequired(TEST_MODULE_NAME))

  v = loader.requireByPath(TEST_MODULE_NAME..'.a.a2')
  lu.assertIs(v, 'A string value')

  v = loader.requireByPath(TEST_MODULE_NAME..'.unknown', true)
  lu.assertNil(v)

  lu.assertIs(loader.requireByPath(TEST_MODULE_NAME), require(TEST_MODULE_NAME))
end

os.exit(lu.LuaUnit.run())
