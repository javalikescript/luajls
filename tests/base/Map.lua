local lu = require('luaunit')

local Map = require("jls.util.Map")

local function sort(t)
  table.sort(t)
  return t
end

function Test_set()
  local m = Map:new()
  m:set('a', true)
  m:set('b', 'A value')
  m:set('c', 1)
  lu.assertEquals(m, {a = true, b = 'A value', c = 1})
  lu.assertTrue(m:delete('b'))
  lu.assertFalse(m:delete('b'))
  lu.assertEquals(m, {a = true, c = 1})
  m:clear()
  lu.assertEquals(m, {})
end

function Test_get()
  local m = Map:new()
  m:set('a', true)
  m:set('b', 'A value')
  m:set('c', 1)
  lu.assertEquals(m:get('a'), true)
  lu.assertEquals(m:get('b'), 'A value')
  lu.assertEquals(m:get('c'), 1)
end

function Test_has()
  local m = Map:new()
  m:set('a', true)
  m:set('b', 'A value')
  m:set('c', 1)
  lu.assertTrue(m:has('a'))
  lu.assertTrue(m:has('b'))
  lu.assertTrue(m:has('c'))
end

function Test_size()
  lu.assertEquals(Map.size({a = true, b = 'A value', c = 1}), 3)
  lu.assertEquals(Map.size({}), 0)
end

function Test_keys()
  lu.assertEquals(sort(Map.keys({a = true, b = 'A value', c = 1})), {'a', 'b', 'c'})
end

function Test_values()
  lu.assertEquals(sort(Map.values({a = 1, b = 2, c = 3})), {1, 2, 3})
end

function Test_spairs()
  local keyValues = {}
  for k, v in Map.spairs({a = 1, c = 3, b = 2}) do
    table.insert(keyValues, {k, v})
  end
  lu.assertEquals(keyValues, {{'a', 1}, {'b', 2}, {'c', 3}})
end

function Test_assign()
  lu.assertEquals(Map.assign({}, {a = true}), {a = true})
  lu.assertEquals(Map.assign({a = true}, {}), {a = true})
  lu.assertEquals(Map.assign({a = true}, {b = true}), {a = true, b = true})
  lu.assertEquals(Map.assign({}, {a = true}, {b = true}), {a = true, b = true})
end

function Test_reverse()
  lu.assertEquals(Map.reverse({k1 = 'v1', k2 = 'v2'}), {v1 = 'k1', v2 = 'k2'})
  lu.assertEquals(Map.reverse({k = 'v'}), {v = 'k'})
  lu.assertEquals(Map.reverse({}), {})
end

os.exit(lu.LuaUnit.run())
