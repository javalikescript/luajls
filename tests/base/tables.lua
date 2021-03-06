local lu = require('luaunit')

local tables = require("jls.util.tables")

function Test_compare_flat()
  lu.assertEquals(tables.compare({}, {a = true}), {a = true})
  lu.assertEquals(tables.compare({a = false}, {a = true}), {a = true})
  lu.assertEquals(tables.compare({a = true}, {a = false}), {a = false})
  lu.assertEquals(tables.compare({a = true}, {}), {_deleted = {'a'}})
  lu.assertEquals(tables.compare({a = true, b = 1, c = 'Hello'}, {a = true, c = 'Hello'}), {_deleted = {'b'}})
  lu.assertEquals(tables.compare({a = true, b = 1, c = 'Hello'}, {a = true, c = 'Hello 2'}), {c = 'Hello 2', _deleted = {'b'}})
end

function Test_compare_flat_no_diff()
  lu.assertIsNil(tables.compare({a = true}, {a = true}))
  lu.assertIsNil(tables.compare({a = true, b = 1, c = 'Hello'}, {a = true, b = 1, c = 'Hello'}))
  lu.assertIsNil(tables.compare({a = true, b = 1, c = 'Hello'}, {a = true, c = 'Hello', b = 1}))
  lu.assertIsNil(tables.compare({}, {}))
end

local function assertPatchCompare(ot, nt)
  lu.assertEquals(tables.patch(ot, tables.compare(ot, nt)), nt)
end

function Test_patch_flat()
  lu.assertEquals(tables.patch({}, {a = true}), {a = true})
  lu.assertEquals(tables.patch({a = true}, {}), {a = true})
  lu.assertEquals(tables.patch({a = false}, {}), {a = false})
  lu.assertEquals(tables.patch({a = true}, {_deleted = {'a'}}), {})
end

function Test_patch_compare()
  assertPatchCompare({}, {a = true})
  assertPatchCompare({a = true}, {})
  assertPatchCompare({a = false}, {a = true})
end

function Test_merge_flat()
  lu.assertEquals(tables.merge({}, {a = true}), {a = true})
  lu.assertEquals(tables.merge({a = true}, {}), {a = true})
  lu.assertEquals(tables.merge({a = true}, {b = true}), {a = true, b = true})
end

function Test_merge_deep()
  lu.assertEquals(tables.merge({a = {a = true}}, {a = {b = true}}), {a = {a = true, b = true}})
  lu.assertEquals(tables.merge({a = true}, {a = {b = true}}), {a = {b = true}})
  lu.assertEquals(tables.merge({a = {a = true}}, {a = true}), {a = true})
end

function Test_getPath_flat()
  lu.assertEquals(tables.getPath({a = 'A value'}, '/'), {a = 'A value'})
  lu.assertEquals(tables.getPath({a = 'A value'}, 'a'), 'A value')
  lu.assertEquals(tables.getPath({a = 'A value'}, '/a'), 'A value')
  lu.assertIsNil(tables.getPath({a = 'A value'}, 'b'))
  lu.assertEquals(tables.getPath({a = {b = 'A value'}}, 'a'), {b = 'A value'})
end

function Test_getPath_tree()
  lu.assertEquals(tables.getPath({a = {b = 'A value'}}, 'a/b'), 'A value')
  lu.assertEquals(tables.getPath({a = {b = 'A value'}}, '/a/b'), 'A value')
end

function Test_getPath_list()
  lu.assertEquals(tables.getPath({a = {'x', 'y', 'z'}}, 'a/1'), 'x')
  lu.assertEquals(tables.getPath({a = {'x', 'y', 'z'}}, 'a/[2]'), 'y')
  lu.assertEquals(tables.getPath({a = {'x', 'y', 'z'}}, 'a/3'), 'z')
  lu.assertNil(tables.getPath({a = {'x', 'y', 'z'}}, 'a/[4]'))
end

function Test_getPath_defaultValue()
  lu.assertEquals(tables.getPath({a = {b = 'A value'}}, 'c'), nil)
  lu.assertEquals(tables.getPath({a = {b = 'A value'}}, 'a/c'), nil)
  lu.assertEquals(tables.getPath({a = {b = 'A value'}}, 'a/b/c'), nil)
  lu.assertEquals(tables.getPath({a = {b = 'A value'}}, 'a/c', 'Another value'), 'Another value')
end

local function assertSetPath(t, p, v, nt)
  tables.setPath(t, p, v)
  lu.assertEquals(t, nt)
end

function Test_setPath_flat()
  assertSetPath({a = 'A value'}, 'a', 'New value', {a = 'New value'})
  assertSetPath({a = 'A value'}, '/a', 'New value', {a = 'New value'})
  assertSetPath({a = 'A value'}, 'b', 'New value', {a = 'A value', b = 'New value'})
end

function Test_setPath_tree()
  assertSetPath({a = {b = 'A value'}}, 'a/b', 'New value', {a = {b = 'New value'}})
  assertSetPath({a = 'A value'}, 'a/b', 'New value', {a = {b = 'New value'}})
  assertSetPath({a = {b = 'A value'}}, 'a/c/d', 'New value', {a = {b = 'A value', c = {d = 'New value'}}})
end

function Test_setPath_list()
  assertSetPath({a = {'x', 'y', 'z'}}, 'a/[2]', 'New y', {a = {'x', 'New y', 'z'}})
  assertSetPath({a = {'x', 'y', 'z'}}, 'a/2', 'New y', {a = {'x', 'New y', 'z'}})
end

local function assertMergePath(t, p, v, nt)
  tables.mergePath(t, p, v)
  lu.assertEquals(t, nt)
end

function Test_mergePath_flat()
  assertMergePath({a = {b = true}}, 'a', {c = true}, {a = {b = true, c = true}})
end

local function assertRemovePath(t, p, nt)
  tables.removePath(t, p)
  lu.assertEquals(t, nt)
end

function Test_removePath_flat()
  assertRemovePath({a = 'A value'}, 'a', {})
  assertRemovePath({a = 'A value', b = 'Another value'}, 'b', {a = 'A value'})
end

function Test_removePath_tree()
  assertRemovePath({a = {b = 'A value'}}, 'a/b', {a = {}})
end

function Test_removePath_list()
  assertRemovePath({a = {'x', 'y', 'z'}}, 'a/[2]', {a = {'x', 'z'}})
end

function Test_mapValuesByPath()
  lu.assertEquals(tables.mapValuesByPath({a = {b = 'A value'}}), {['/a/b'] = 'A value'})
  lu.assertEquals(tables.mapValuesByPath({a = {b = 'A value', c = 1}, d = true}), {['/a/b'] = 'A value', ['/a/c'] = 1, ['/d'] = true})
end

function Test_createArgumentTable()
  lu.assertEquals(tables.createArgumentTable({'test'}), {[''] = 'test'})
  lu.assertEquals(tables.createArgumentTable({'-f', 'file'}), {['-f'] = 'file'})
  lu.assertEquals(tables.createArgumentTable({'-f', 'file', '-d', 'dir'}), {['-d'] = 'dir', ['-f'] = 'file'})
  lu.assertEquals(tables.createArgumentTable({'test', '-f', 'file'}), {[''] = 'test', ['-f'] = 'file'})
  lu.assertEquals(tables.createArgumentTable({'-a', '1', '-a', '2'}), {['-a'] = {'1', '2'}})
end

function Test_mergeValuesByPath()
  lu.assertEquals(tables.mergeValuesByPath({}, {a = {b = 'A value'}}), {['/a/b'] = {new = 'A value'}})
  lu.assertEquals(tables.mergeValuesByPath({a = {b = 'A value'}}, {}), {['/a/b'] = {old = 'A value'}})
  lu.assertEquals(tables.mergeValuesByPath({a = {b = 'A', c = 'C'}}, {a = {b = 'B', d = 'D'}}), {['/a/b'] = {old = 'A', new = 'B'}, ['/a/c'] = {old = 'C'}, ['/a/d'] = {new = 'D'}})
end

function Test_parse()
  lu.assertEquals(tables.parse('{a="Hi",}'), {a = "Hi"})
end

function Test_stringify()
  lu.assertEquals(tables.stringify(1), '1')
  lu.assertEquals(tables.stringify(1.2), '1.2')
  lu.assertEquals(tables.stringify(true), 'true')
  lu.assertEquals(tables.stringify("Hi"), '"Hi"')
  lu.assertEquals(tables.stringify("\0\1"), '"\\0\\1"')
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

local function getSchemaValueOrFail(schema, value, translateValues)
  local result, err = tables.getSchemaValue(schema, value, translateValues)
  if err then
    lu.fail(err)
    return
  end
  return result
end

function Test_getSchemaValue_simple()
  lu.assertEquals(getSchemaValueOrFail({type = 'integer'}, 0), 0)
  lu.assertEquals(getSchemaValueOrFail({type = 'integer'}, 1), 1)
  lu.assertEquals(getSchemaValueOrFail({type = 'integer'}, 1.0), 1)
  lu.assertNil(tables.getSchemaValue({type = 'integer'}, 1.2))
  lu.assertNil(tables.getSchemaValue({type = 'integer'}, {}))
  lu.assertEquals(getSchemaValueOrFail({type = 'number'}, 1.2), 1.2)
  lu.assertNil(tables.getSchemaValue({type = 'number'}, {}))
  lu.assertEquals(getSchemaValueOrFail({type = 'string'}, 'Hello'), 'Hello')
  lu.assertNil(tables.getSchemaValue({type = 'string'}, {}))
  lu.assertEquals(getSchemaValueOrFail({type = 'boolean'}, true), true)
  lu.assertEquals(getSchemaValueOrFail({type = 'boolean'}, false), false)
  lu.assertNil(tables.getSchemaValue({type = 'array'}, 'String'))
  lu.assertNil(tables.getSchemaValue({type = 'object'}, 'String'))
end

local function assertSchemaValueTranslated(schema, value, expextedValue)
  lu.assertNil(tables.getSchemaValue(schema, value, false))
  lu.assertEquals(getSchemaValueOrFail(schema, value, true), expextedValue)
end

function Test_getSchemaValue_translated()
  assertSchemaValueTranslated({type = 'integer'}, '1', 1)
  assertSchemaValueTranslated({type = 'number'}, '1.2', 1.2)
  assertSchemaValueTranslated({type = 'string'}, 1.2, '1.2')
  assertSchemaValueTranslated({type = 'string'}, true, 'true')
  assertSchemaValueTranslated({type = 'boolean'}, 'true', true)
  assertSchemaValueTranslated({type = 'boolean'}, 'false', false)
end

function Test_getSchemaValue_object()
  local schema = {
    type = 'object',
    properties = {
      name = {
        type = 'string'
      },
      count = {
        type = 'integer',
        default = 1
      },
      available = {
        type = 'boolean',
        default = false
      },
    }
  }
  lu.assertEquals(getSchemaValueOrFail(schema, {name = 'Bag', count = 3, available = true}, true),
    {name = 'Bag', count = 3, available = true})
  lu.assertEquals(getSchemaValueOrFail(schema, {name = 'Tea', count = '2', available = 'false'}, true),
    {name = 'Tea', count = 2, available = false})
  lu.assertEquals(getSchemaValueOrFail(schema, {name = 'Cup'}, true), {name = 'Cup', count = 1, available = false})
end

function Test_createArgumentTableWithCommas()
  local arguments = {'-h', '-x', 'y', '-u', 'v', 'w'}
  local t = tables.createArgumentTable(arguments, {keepComma = true})
  lu.assertEquals(tables.getArgument(t, '-x'), 'y')
  lu.assertEquals(tables.getArgument(t, '-u'), 'v')
  lu.assertNil(tables.getArgument(t, '-t'))
  lu.assertNotNil(tables.getArgument(t, '-h'))
end

function Test_createArgumentTable()
  local arguments = {'-h', '-x', 'y', '-u', 'v', 'w'}
  local t = tables.createArgumentTable(arguments)
  lu.assertEquals(tables.getArgument(t, 'x'), 'y')
  lu.assertEquals(tables.getArgument(t, 'u'), 'v')
  lu.assertNil(tables.getArgument(t, 't'))
  lu.assertNotNil(tables.getArgument(t, 'h'))
end

function Test_createArgumentTablePath()
  local arguments = {'-h', '-x', 'y', '-a.b', 'v', '-a.c', 'w', 'w'}
  local t = tables.createArgumentTable(arguments)
  tables.merge(t, {a = {c = 'ww', d = 'x'}}, true)
  lu.assertEquals(tables.getArgument(t, 'x'), 'y')
  lu.assertEquals(tables.getArgument(t, 'a.b'), 'v')
  lu.assertEquals(tables.getArgument(t, 'a.c'), 'w')
  lu.assertEquals(tables.getArgument(t, 'a.d'), 'x')
  lu.assertNil(tables.getArgument(t, 't'))
  lu.assertNotNil(tables.getArgument(t, 'h'))
end

os.exit(lu.LuaUnit.run())
