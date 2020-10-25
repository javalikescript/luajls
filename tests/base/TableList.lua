local lu = require('luaunit')

local TableList = require('jls.util.TableList')

function Test_size()
  local list = TableList:new('1', '2')
  lu.assertEquals(list:size(), 2)
  list:add('3')
  lu.assertEquals(list:size(), 3)
end

function Test_add()
  local e1 = {}
  local e2 = {}
  local list = TableList:new()
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
  local list = TableList:new(e1, e2)
  lu.assertEquals(#list, 2)
  lu.assertIs(list[1], e1)
  lu.assertIs(list[2], e2)
end

function Test_init()
  local e1 = {}
  local e2 = {}
  local list = TableList:new(e1, e2)
  lu.assertEquals(list:size(), 2)
  lu.assertIs(list:get(1), e1)
  lu.assertIs(list:get(2), e2)
end

function Test_clone()
  local list = TableList:new('1', '2', '3')
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
  local list = TableList:new(e1, e2, e3)
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
  local list = TableList:new('1', '2', '3')
  lu.assertEquals(list, {'1', '2', '3'})
  lu.assertIs(list:remove(2), '2')
  lu.assertEquals(list, {'1', '3'})
end

function Test_iterator()
  local list = TableList:new('1', '2', '3')
  local tl = {}
  for _, v in list:iterator() do
    table.insert(tl, v)
  end
  lu.assertEquals(#tl, 3)
  lu.assertEquals(tl, {'1', '2', '3'})
end

function Test_reverseIterator()
  local list = TableList:new('1', '2', '3')
  local tl = {}
  for _, v in list:reverseIterator() do
    table.insert(tl, v)
  end
  lu.assertEquals(#tl, 3)
  lu.assertEquals(tl, {'3', '2', '1'})
end

function Test_indexOf()
  local list = TableList:new('1', '2', '3', '2')
  lu.assertIs(list:indexOf('1'), 1)
  lu.assertIs(list:indexOf('2'), 2)
  lu.assertIs(list:indexOf('3'), 3)
  lu.assertIsNil(list:indexOf('4'))
end

function Test_contains()
  local list = TableList:new('1', '2', '3', '2')
  lu.assertIsTrue(list:contains('1'), 1)
  lu.assertIsTrue(list:contains('2'), 2)
  lu.assertIsTrue(list:contains('3'), 3)
  lu.assertIsFalse(list:contains('4'))
end

function Test_lastIndexOf()
  local list = TableList:new('1', '2', '3', '2')
  lu.assertIs(list:lastIndexOf('1'), 1)
  lu.assertIs(list:lastIndexOf('2'), 4)
  lu.assertIs(list:lastIndexOf('3'), 3)
  lu.assertIsNil(list:lastIndexOf('4'))
end

function Test_removeFirst()
  local list = TableList:new('1', '2', '3', '2')
  lu.assertEquals(list:size(), 4)
  lu.assertIsTrue(list:removeFirst('2'))
  lu.assertEquals(list:size(), 3)
  lu.assertEquals(list, {'1', '3', '2'})
  lu.assertIsFalse(list:removeFirst('4'))
  lu.assertEquals(list:size(), 3)
  lu.assertEquals(list, {'1', '3', '2'})
end

function Test_removeLast()
  local list = TableList:new('1', '2', '3', '2')
  lu.assertEquals(list:size(), 4)
  lu.assertIsTrue(list:removeLast('2'))
  lu.assertEquals(list:size(), 3)
  lu.assertEquals(list, {'1', '2', '3'})
  lu.assertIsFalse(list:removeLast('4'))
  lu.assertEquals(list:size(), 3)
  lu.assertEquals(list, {'1', '2', '3'})
end

function Test_removeAll()
  local list = TableList:new('1', '2', '3', '2')
  lu.assertEquals(list:size(), 4)
  list:removeAll('2')
  lu.assertEquals(list:size(), 2)
  lu.assertEquals(list, {'1', '3'})
  list:removeAll('4')
  lu.assertEquals(list:size(), 2)
  lu.assertEquals(list, {'1', '3'})
end

function Test_concat()
  lu.assertEquals(TableList.concat({}, ','), '')
  lu.assertEquals(TableList.concat({'a'}, ','), 'a')
  lu.assertEquals(TableList.concat({'a', 'b', 'c'}, ','), 'a,b,c')
  lu.assertEquals(TableList.concat({'a', 'b', 'c'}), 'abc')
  local t = {}
  lu.assertEquals(TableList.concat({'a', t, 1, true}, ','), 'a,'..tostring(t)..',1,true')
end

os.exit(lu.LuaUnit.run())
