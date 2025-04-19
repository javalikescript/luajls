local lu = require('luaunit')

local loader = require('jls.lang.loader')

local TEST_MODULE_NAME = 'mod_test'
local TEST_2_MODULE_NAME = 'mod_test_2'
local UNKNOWN_MODULE_NAME = 'not_mod_test'

TestLoader = {}

function TestLoader:setUp()
  package.resource = nil
  loader.addLuaPath('tests/?.lua')
  loader.unload(TEST_MODULE_NAME)
  loader.unload(TEST_2_MODULE_NAME)
end

function TestLoader:tearDown()
  loader.resetLuaPath()
end

function TestLoader:test_findPath()
  lu.assertEvalToFalse(loader.findPath('a', ''))
  lu.assertEvalToTrue(loader.findPath('a', 'a'))
  lu.assertEvalToTrue(loader.findPath('b', 'a;b'))
  lu.assertEvalToTrue(loader.findPath('b', 'a;b;c'))
  lu.assertEvalToFalse(loader.findPath('b', 'a;bb;c'))
  lu.assertEvalToTrue(loader.findPath('b', 'a;bb;b;c'))
  lu.assertEvalToTrue(loader.findPath('b', 'b;c'))
end

function TestLoader:test_addLuaPath()
  package.path = 'a;b;c'
  loader.addLuaPath('b')
  lu.assertEquals(package.path, 'a;b;c')
  loader.addLuaPath('d')
  lu.assertEquals(package.path, 'a;b;c;d')
  loader.removeLuaPath('b')
  lu.assertEquals(package.path, 'a;c;d')
  loader.removeLuaPath('d')
  lu.assertEquals(package.path, 'a;c')
  loader.removeLuaPath('a')
  lu.assertEquals(package.path, 'c')
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

function TestLoader:test_lazyFunction()
  lu.assertNil(loader.getRequired(TEST_MODULE_NAME))
  local pfc, fc = 0, 0
  local f = loader.lazyFunction(function(um, m)
    pfc = pfc + 1
    return function()
      fc = fc + 1
      return m
    end
  end, true, UNKNOWN_MODULE_NAME, TEST_MODULE_NAME)
  local mr = require(TEST_MODULE_NAME)
  lu.assertEquals(fc, 0)
  lu.assertEquals(pfc, 0)
  lu.assertIs(f(), mr)
  lu.assertEquals(fc, 1)
  lu.assertEquals(pfc, 1)
  lu.assertIs(f(), mr)
  lu.assertEquals(fc, 2)
  lu.assertEquals(pfc, 1)
end

function TestLoader:test_loadResource()
  loader.addLuaPath('?.lua')
  lu.assertEquals(loader.loadResource('res_test.txt'), 'Resource content')
  lu.assertEquals(loader.loadResource('tests/res_test.txt'), 'Resource content')
  package.resource = {a = 'a content', b = function(n) return 'b:'..n end, ['res_test.txt'] = 'c'}
  lu.assertEquals(loader.loadResource('a'), 'a content')
  lu.assertEquals(loader.loadResource('b'), 'b:b')
  lu.assertEquals(loader.loadResource('res_test.txt'), 'c')
  package.resource = nil
  lu.assertNil(loader.loadResource('a', true))
  lu.assertFalse(pcall(loader.loadResource, 'a'))
end

os.exit(lu.LuaUnit.run())
