local lu = require('luaunit')

local tables = require("jls.util.tables")

function test_compare_flat()
  lu.assertEquals(tables.compare({}, {a = true}), {a = true})
  lu.assertEquals(tables.compare({a = false}, {a = true}), {a = true})
  lu.assertEquals(tables.compare({a = true}, {a = false}), {a = false})
  lu.assertEquals(tables.compare({a = true}, {}), {_deleted = {'a'}})
  lu.assertEquals(tables.compare({a = true, b = 1, c = 'Hello'}, {a = true, c = 'Hello'}), {_deleted = {'b'}})
  lu.assertEquals(tables.compare({a = true, b = 1, c = 'Hello'}, {a = true, c = 'Hello 2'}), {c = 'Hello 2', _deleted = {'b'}})
end

function test_compare_flat_no_diff()
  lu.assertIsNil(tables.compare({a = true}, {a = true}))
  lu.assertIsNil(tables.compare({a = true, b = 1, c = 'Hello'}, {a = true, b = 1, c = 'Hello'}))
  lu.assertIsNil(tables.compare({a = true, b = 1, c = 'Hello'}, {a = true, c = 'Hello', b = 1}))
  lu.assertIsNil(tables.compare({}, {}))
end

function assertPatchCompare(ot, nt)
  lu.assertEquals(tables.patch(ot, tables.compare(ot, nt)), nt)
end

function test_patch_flat()
  lu.assertEquals(tables.patch({}, {a = true}), {a = true})
  lu.assertEquals(tables.patch({a = true}, {}), {a = true})
  lu.assertEquals(tables.patch({a = false}, {}), {a = false})
  lu.assertEquals(tables.patch({a = true}, {_deleted = {'a'}}), {})
end

function test_patch_compare()
  assertPatchCompare({}, {a = true})
  assertPatchCompare({a = true}, {})
  assertPatchCompare({a = false}, {a = true})
end

function test_merge_flat()
  lu.assertEquals(tables.merge({}, {a = true}), {a = true})
  lu.assertEquals(tables.merge({a = true}, {}), {a = true})
  lu.assertEquals(tables.merge({a = true}, {b = true}), {a = true, b = true})
end

function test_merge_deep()
  lu.assertEquals(tables.merge({a = {a = true}}, {a = {b = true}}), {a = {a = true, b = true}})
  lu.assertEquals(tables.merge({a = true}, {a = {b = true}}), {a = {b = true}})
  lu.assertEquals(tables.merge({a = {a = true}}, {a = true}), {a = true})
end

function test_getPath_flat()
  lu.assertEquals(tables.getPath({a = 'A value'}, '/'), {a = 'A value'})
  lu.assertEquals(tables.getPath({a = 'A value'}, 'a'), 'A value')
  lu.assertEquals(tables.getPath({a = 'A value'}, '/a'), 'A value')
  lu.assertIsNil(tables.getPath({a = 'A value'}, 'b'))
  lu.assertEquals(tables.getPath({a = {b = 'A value'}}, 'a'), {b = 'A value'})
end

function test_getPath_tree()
  lu.assertEquals(tables.getPath({a = {b = 'A value'}}, 'a/b'), 'A value')
  lu.assertEquals(tables.getPath({a = {b = 'A value'}}, '/a/b'), 'A value')
end

function test_getPath_list()
  lu.assertEquals(tables.getPath({a = {'x', 'y', 'z'}}, 'a/2'), 'y')
end

function test_getPath_defaultValue()
  lu.assertEquals(tables.getPath({a = {b = 'A value'}}, 'c'), nil)
  lu.assertEquals(tables.getPath({a = {b = 'A value'}}, 'a/c'), nil)
  lu.assertEquals(tables.getPath({a = {b = 'A value'}}, 'a/b/c'), nil)
  lu.assertEquals(tables.getPath({a = {b = 'A value'}}, 'a/c', 'Another value'), 'Another value')
end

function assertSetPath(t, p, v, nt)
  tables.setPath(t, p, v)
  lu.assertEquals(t, nt)
end

function test_setPath_flat()
  assertSetPath({a = 'A value'}, 'a', 'New value', {a = 'New value'})
  assertSetPath({a = 'A value'}, '/a', 'New value', {a = 'New value'})
  assertSetPath({a = 'A value'}, 'b', 'New value', {a = 'A value', b = 'New value'})
end

function test_setPath_tree()
  assertSetPath({a = {b = 'A value'}}, 'a/b', 'New value', {a = {b = 'New value'}})
  assertSetPath({a = 'A value'}, 'a/b', 'New value', {a = {b = 'New value'}})
  assertSetPath({a = {b = 'A value'}}, 'a/c/d', 'New value', {a = {b = 'A value', c = {d = 'New value'}}})
end

function test_setPath_list()
  assertSetPath({a = {'x', 'y', 'z'}}, 'a/2', 'New y', {a = {'x', 'New y', 'z'}})
end

function assertMergePath(t, p, v, nt)
  tables.mergePath(t, p, v)
  lu.assertEquals(t, nt)
end

function test_mergePath_flat()
  assertMergePath({a = {b = true}}, 'a', {c = true}, {a = {b = true, c = true}})
end

function assertRemovePath(t, p, nt)
  tables.removePath(t, p)
  lu.assertEquals(t, nt)
end

function test_removePath_flat()
  assertRemovePath({a = 'A value'}, 'a', {})
  assertRemovePath({a = 'A value', b = 'Another value'}, 'b', {a = 'A value'})
end

function test_removePath_tree()
  assertRemovePath({a = {b = 'A value'}}, 'a/b', {a = {}})
end

function test_removePath_list()
  assertRemovePath({a = {'x', 'y', 'z'}}, 'a/2', {a = {'x', 'z'}})
end

function test_mapValuesByPath()
  lu.assertEquals(tables.mapValuesByPath({a = {b = 'A value'}}), {['/a/b'] = 'A value'})
  lu.assertEquals(tables.mapValuesByPath({a = {b = 'A value', c = 1}, d = true}), {['/a/b'] = 'A value', ['/a/c'] = 1, ['/d'] = true})
end

function test_createArgumentTable()
  lu.assertEquals(tables.createArgumentTable({'test'}), {[''] = 'test'})
  lu.assertEquals(tables.createArgumentTable({'-f', 'file'}), {['-f'] = 'file'})
  lu.assertEquals(tables.createArgumentTable({'-f', 'file', '-d', 'dir'}), {['-d'] = 'dir', ['-f'] = 'file'})
  lu.assertEquals(tables.createArgumentTable({'test', '-f', 'file'}), {[''] = 'test', ['-f'] = 'file'})
  lu.assertEquals(tables.createArgumentTable({'-a', '1', '-a', '2'}), {['-a'] = {'1', '2'}})
end

function test_mergeValuesByPath()
  lu.assertEquals(tables.mergeValuesByPath({}, {a = {b = 'A value'}}), {['/a/b'] = {new = 'A value'}})
  lu.assertEquals(tables.mergeValuesByPath({a = {b = 'A value'}}, {}), {['/a/b'] = {old = 'A value'}})
  lu.assertEquals(tables.mergeValuesByPath({a = {b = 'A', c = 'C'}}, {a = {b = 'B', d = 'D'}}), {['/a/b'] = {old = 'A', new = 'B'}, ['/a/c'] = {old = 'C'}, ['/a/d'] = {new = 'D'}})
end

function test_stringify()
  lu.assertEquals(tables.stringify(1), '1')
  lu.assertEquals(tables.stringify(1.2), '1.2')
  lu.assertEquals(tables.stringify(true), 'true')
  lu.assertEquals(tables.stringify("Hi"), '"Hi"')
  lu.assertEquals(tables.stringify({}), '{}')
  -- table map
  lu.assertEquals(tables.stringify({a = "Hi"}), '{a="Hi",}')
  lu.assertEquals(tables.stringify({["b"] = 2}), '{b=2,}')
  lu.assertEquals(tables.stringify({["1"] = 2}), '{["1"]=2,}')
  lu.assertEquals(tables.stringify({[5] = 2}), '{[5]=2,}')
  lu.assertEquals(tables.stringify({c = false}), '{c=false,}')
  lu.assertEquals(tables.stringify({["b "] = 2}), '{["b "]=2,}')
  -- table list
  lu.assertEquals(tables.stringify({1, true, "Hi"}), '{1,true,"Hi",}')
end

os.exit(lu.LuaUnit.run())
