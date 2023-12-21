local lu = require('luaunit')

local List = require('jls.util.List')

function Test_size()
  local list = List:new('1', '2')
  lu.assertEquals(list:size(), 2)
  list:add('3')
  lu.assertEquals(list:size(), 3)
end

function Test_add()
  local e1 = {}
  local e2 = {}
  local list = List:new()
  list:add(e1)
  lu.assertEquals(list:size(), 1)
  list:add(e2)
  lu.assertEquals(list:size(), 2)
  lu.assertIs(list:get(1), e1)
  lu.assertIs(list:get(2), e2)
end

function Test_table()
  local e1 = {}
  local e2 = {}
  local list = List:new(e1, e2)
  lu.assertEquals(#list, 2)
  lu.assertIs(list[1], e1)
  lu.assertIs(list[2], e2)
end

function Test_init()
  local e1 = {}
  local e2 = {}
  local list = List:new(e1, e2)
  lu.assertEquals(list:size(), 2)
  lu.assertIs(list:get(1), e1)
  lu.assertIs(list:get(2), e2)
end

function Test_clone()
  local list = List:new('1', '2', '3')
  lu.assertEquals(list, {'1', '2', '3'})
  local cl = list:clone()
  lu.assertEquals(list, {'1', '2', '3'})
  lu.assertEquals(cl, {'1', '2', '3'})
  list:add('4')
  lu.assertEquals(list, {'1', '2', '3', '4'})
  lu.assertEquals(cl, {'1', '2', '3'})
  cl:add('5')
  lu.assertEquals(list, {'1', '2', '3', '4'})
  lu.assertEquals(cl, {'1', '2', '3', '5'})
end

function Test_remove()
  local e1 = {}
  local e2 = {}
  local e3 = {}
  local list = List:new(e1, e2, e3)
  lu.assertEquals(list:size(), 3)
  lu.assertIs(list:get(1), e1)
  lu.assertIs(list:get(2), e2)
  lu.assertIs(list:get(3), e3)
  lu.assertIs(list:remove(2), e2)
  lu.assertEquals(list:size(), 2)
  lu.assertIs(list:get(1), e1)
  lu.assertIs(list:get(2), e3)
end

function Test_remove_2()
  local list = List:new('1', '2', '3')
  lu.assertEquals(list, {'1', '2', '3'})
  lu.assertIs(list:remove(2), '2')
  lu.assertEquals(list, {'1', '3'})
end

function Test_iterator()
  local list = List:new('1', '2', '3')
  local tl = {}
  for _, v in list:iterator() do
    table.insert(tl, v)
  end
  lu.assertEquals(#tl, 3)
  lu.assertEquals(tl, {'1', '2', '3'})
end

function Test_reverseIterator()
  local list = List:new('1', '2', '3')
  local tl = {}
  for _, v in list:reverseIterator() do
    table.insert(tl, v)
  end
  lu.assertEquals(#tl, 3)
  lu.assertEquals(tl, {'3', '2', '1'})
end

function Test_indexOf()
  local list = List:new('1', '2', '3', '2')
  lu.assertIs(list:indexOf('1'), 1)
  lu.assertIs(list:indexOf('2'), 2)
  lu.assertIs(list:indexOf('3'), 3)
  lu.assertIs(list:indexOf('4'), 0)
end

function Test_contains()
  local list = List:new('1', '2', '3', '2')
  lu.assertIsTrue(list:contains('1'), 1)
  lu.assertIsTrue(list:contains('2'), 2)
  lu.assertIsTrue(list:contains('3'), 3)
  lu.assertIsFalse(list:contains('4'))
end

function Test_lastIndexOf()
  local list = List:new('1', '2', '3', '2')
  lu.assertIs(list:lastIndexOf('1'), 1)
  lu.assertIs(list:lastIndexOf('2'), 4)
  lu.assertIs(list:lastIndexOf('3'), 3)
  lu.assertIsNil(list:lastIndexOf('4'))
end

function Test_removeFirst()
  local list = List:new('1', '2', '3', '2')
  lu.assertEquals(list:size(), 4)
  lu.assertIsTrue(list:removeFirst('2'))
  lu.assertEquals(list:size(), 3)
  lu.assertEquals(list, {'1', '3', '2'})
  lu.assertIsFalse(list:removeFirst('4'))
  lu.assertEquals(list:size(), 3)
  lu.assertEquals(list, {'1', '3', '2'})
end

function Test_removeLast()
  local list = List:new('1', '2', '3', '2')
  lu.assertEquals(list:size(), 4)
  lu.assertIsTrue(list:removeLast('2'))
  lu.assertEquals(list:size(), 3)
  lu.assertEquals(list, {'1', '2', '3'})
  lu.assertIsFalse(list:removeLast('4'))
  lu.assertEquals(list:size(), 3)
  lu.assertEquals(list, {'1', '2', '3'})
end

function Test_removeAll()
  local list = List:new('1', '2', '3', '2')
  lu.assertEquals(list:size(), 4)
  list:removeAll('2')
  lu.assertEquals(list:size(), 2)
  lu.assertEquals(list, {'1', '3'})
  list:removeAll('4')
  lu.assertEquals(list:size(), 2)
  lu.assertEquals(list, {'1', '3'})
end

function Test_join()
  lu.assertEquals(List.join({}, ','), '')
  lu.assertEquals(List.join({'a'}, ','), 'a')
  lu.assertEquals(List.join({'a', 'b', 'c'}, ','), 'a,b,c')
  lu.assertEquals(List.join({'a', 'b', 'c'}), 'abc')
  local t = {}
  lu.assertEquals(List.join({'a', t, 1, true}, ','), 'a,'..tostring(t)..',1,true')
end

function Test_concat()
  lu.assertIsNil(List.concat())
  lu.assertEquals(List.concat({'a'}), {'a'})
  lu.assertEquals(List.concat({'a', 'b', 'c'}), {'a', 'b', 'c'})
  lu.assertEquals(List.concat({'a'}, {'b', 'c'}), {'a', 'b', 'c'})
  lu.assertEquals(List.concat({'a', 'b'}, {'c'}), {'a', 'b', 'c'})
  lu.assertEquals(List.concat({'a'}, {'b'}, {'c'}), {'a', 'b', 'c'})
  lu.assertEquals(List.concat({'a'}, {'b'}, nil, {'c'}), {'a', 'b', 'c'})
  lu.assertEquals(List.concat({'a'}, 'b', {'c'}), {'a', 'b', 'c'})
end

function Test_map()
  local function f(v, i)
    return v..tostring(i)
  end
  lu.assertEquals(List.map({}, {'a', 'b'}, f), {'a1', 'b2'})
  lu.assertEquals(List.map({}, {}, f), {})
  lu.assertEquals(List.map({'a', 'b'}, f), {'a1', 'b2'})
end

function Test_addAll()
  lu.assertEquals(List.addAll({}, {'a', 'b'}), {'a', 'b'})
  lu.assertEquals(List.addAll({'a', 'b'}, {}), {'a', 'b'})
  lu.assertEquals(List.addAll({'a'}, {'b'}), {'a', 'b'})
end

local table_pack = table.pack or function(...)
  return {n = select('#', ...), ...}
end

function Test_isList()
  lu.assertFalse(List.isList(nil))
  lu.assertFalse(List.isList(1))
  lu.assertFalse(List.isList(true))
  lu.assertFalse(List.isList(''))
  lu.assertFalse(List.isList({a = 1, b = 2}))
  lu.assertFalse(List.isList({'aa', a = 1, b = 2}))
  lu.assertFalse(List.isList({}))
  lu.assertFalse(List.isList({'a', nil, 'b'}))
  lu.assertTrue(List.isList({}, nil, true))
  lu.assertTrue(List.isList({'a'}))
  lu.assertTrue(List.isList({'a', 'b'}))
  lu.assertTrue(List.isList({'a', 'b', 'c'}))
  lu.assertTrue(List.isList({'a', nil, 'b'}, true))
  lu.assertFalse(List.isList(table_pack()))
  lu.assertTrue(List.isList(table_pack('a')))
  lu.assertTrue(List.isList(table_pack('a', 'b')))
  lu.assertFalse(List.isList(table_pack('a', nil, 'b')))
  lu.assertTrue(List.isList(table_pack('a', nil, 'b'), true))
end

function Test_reduce()
  local function f(a, v)
    return a + v
  end
  lu.assertEquals(List.reduce({1, 2}, f), 3)
  lu.assertEquals(List.reduce({1, 2}, f, 10), 13)
end

os.exit(lu.LuaUnit.run())
