local lu = require('luaunit')

local tables = require('jls.util.tables')
local List = require('jls.util.List')
local Map = require('jls.util.Map')

local table_pack = table.pack or function(...)
  return {n = select('#', ...), ...}
end
---@diagnostic disable-next-line: deprecated
local table_unpack = table.unpack or _G.unpack

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

function Test_compare_list()
  lu.assertEquals(tables.compare({}, {true}), {true})
  lu.assertEquals(tables.compare({true}, {}), {_deleted = {1}})
  lu.assertEquals(tables.compare({1, 2, 3}, {1, 4, 3}), {[2] = 4})
  lu.assertEquals(tables.compare({true}, {false}), {[1] = false})

  lu.assertEquals(tables.compare({}, {true}, true), {_list = true, ['1'] = true})
  lu.assertEquals(tables.compare({true}, {}, true), {_deleted = {1}})
  lu.assertEquals(tables.compare({1, 2, 3}, {1, 4, 3}, true), {_list = true, ['2'] = 4})
  lu.assertEquals(tables.compare({true}, {false}, true), {_list = true, ['1'] = false})
  lu.assertEquals(tables.compare({1, 2, 3}, {1, 4}, true), {_list = true, _deleted = {3}, ['2'] = 4})
  lu.assertEquals(tables.compare({1, 2, 3}, {1, nil, 3}, true), {_deleted={2}})
  lu.assertEquals(tables.compare({1, 2, 3}, {1, nil, 4}, true), {_list = true, _deleted={2}, ['3'] = 4})

  lu.assertEquals(tables.compare({1, 2, 3}, {n = 3, 1, 4, 3}, true), {_list = true, n = 3, ['2'] = 4})
  lu.assertEquals(tables.compare({1, 2, 3}, {n = 4, 1, 2, 3}, true), {n = 4})
  lu.assertEquals(tables.compare({n = 3, 1, 2, 3}, {n = 3, 1, nil, 3}, true), {_deleted={2}})
end

function Test_patch_flat()
  lu.assertEquals(tables.patch({}, {a = true}), {a = true})
  lu.assertEquals(tables.patch({a = true}, {}), {a = true})
  lu.assertEquals(tables.patch({a = false}, {}), {a = false})
  lu.assertEquals(tables.patch({a = true}, {_deleted = {'a'}}), {})
end

function Test_patch_list()
  lu.assertEquals(tables.patch({}, {a = true}), {a = true})
end

local function assertPatchCompare(ot, nt)
  local diff = tables.compare(ot, nt)
  if diff == nil then
    lu.assertEquals(ot, nt)
  else
    lu.assertEquals(tables.patch(ot, diff), nt)
    lu.assertEquals(tables.patch(ot, tables.compare(ot, nt, true)), nt)
  end
end

function Test_patch_compare()
  assertPatchCompare({}, {})
  assertPatchCompare({}, {a = true})
  assertPatchCompare({a = true}, {})
  assertPatchCompare({a = false}, {a = true})
  assertPatchCompare({true}, {})
  assertPatchCompare({}, {true})
  assertPatchCompare({true}, {false})
  assertPatchCompare({1, 2, 3}, {1, 4})
  assertPatchCompare({1, 2, 3, n = 3}, {1, 4, n = 2})
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
  lu.assertEquals(tables.getPath({a = {b = 'A value'}}, '/a/["b"]'), 'A value')
  lu.assertEquals(tables.getPath({a = {b = 'A value'}}, '/a["b"]'), 'A value')
end

function Test_getPath_list()
  lu.assertEquals(tables.getPath({a = {'x', 'y', 'z'}}, 'a/1'), 'x')
  lu.assertEquals(tables.getPath({a = {'x', 'y', 'z'}}, 'a/[2]'), 'y')
  lu.assertEquals(tables.getPath({a = {'x', 'y', 'z'}}, 'a[2]'), 'y')
  lu.assertEquals(tables.getPath({a = {'x', 'y', 'z'}}, 'a/3'), 'z')
  lu.assertNil(tables.getPath({a = {'x', 'y', 'z'}}, 'a/[4]'))
  lu.assertEquals(tables.getPath({a = {'x', {b = 'A value'}, 'z'}}, 'a[2]/b'), 'A value')
  lu.assertEquals(tables.getPath({a = {'x', {b = 'A value'}, 'z'}}, 'a[2]["b"]'), 'A value')
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

function Test_setByPath()
  tables.setByPath({a = {x = 1, y = 2}}, {a = {x = 3}})
  lu.assertEquals(tables.setByPath({a = {x = 1, y = 2}}, {a = {x = 3}}), {a = {x = 3, y = 2}})
end

local function assertMergePath(t, p, v, nt)
  local rt = table_pack(tables.mergePath(t, p, v))
  lu.assertEquals(t, nt)
  return table_unpack(rt)
end

function Test_mergePath_flat()
  assertMergePath({a = {b = true}}, 'a', {c = true}, {a = {b = true, c = true}})
end

function Test_mergePath_empty()
  local v = {}
  local r = assertMergePath({a = {b = true}}, 'a/c', v, {a = {b = true, c = {}}})
  lu.assertIs(r, v)
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

function Test_isName()
  lu.assertIsTrue(tables.isName('a_value'))
  lu.assertIsTrue(tables.isName('a1'))
  lu.assertIsTrue(tables.isName('_value'))
  lu.assertIsTrue(tables.isName('B'))
  lu.assertIsFalse(tables.isName('1_value'))
  lu.assertIsFalse(tables.isName('and'))
  lu.assertIsFalse(tables.isName())
  lu.assertIsFalse(tables.isName(1))
end

local function assertParse(parse)
  lu.assertNil(parse('nil'))
  lu.assertNil(parse('os.execute("echo ouch")'))
  lu.assertEquals(parse('"Hi"'), "Hi")
  lu.assertEquals(parse('1'), 1)
  lu.assertEquals(parse('true'), true)
  lu.assertEquals(parse('{a="Hi",b=2,c=true}'), {a = "Hi", b = 2, c = true})
  lu.assertEquals(parse('{"Hi", 2, true}'), {"Hi", 2, true})
  lu.assertEquals(parse('{{"Hi", 2, true}, [3] = {a="Hi",b=2,c=true}}'), {{"Hi", 2, true}, [3] = {a = "Hi", b = 2, c = true}})
end

function Test_parse()
  assertParse(tables.parse)
end

function Test_parseLoad()
  assertParse(tables.parseLoad)
end

function Test_stringify()
  lu.assertEquals(tables.stringify(nil), 'nil')
  lu.assertEquals(tables.stringify(1), '1')
  lu.assertEquals(tables.stringify(1.2), '1.2')
  lu.assertEquals(tables.stringify(true), 'true')
  lu.assertEquals(tables.stringify("Hi"), '"Hi"')
  if _VERSION >= 'Lua 5.2' then
    lu.assertEquals(tables.stringify("\0\1"), '"\\0\\1"')
  end
  lu.assertEquals(tables.stringify({}), '{}')
  -- table map
  lu.assertEquals(tables.stringify({a = "Hi"}), '{a="Hi",}')
  lu.assertEquals(tables.stringify({["b"] = 2}), '{b=2,}')
  lu.assertEquals(tables.stringify({["1"] = 2}), '{["1"]=2,}')
  lu.assertEquals(tables.stringify({[5] = 2}), '{[5]=2,}')
  lu.assertEquals(tables.stringify({c = false}), '{c=false,}')
  lu.assertEquals(tables.stringify({["b "] = 2}), '{["b "]=2,}')
  lu.assertEquals(tables.stringify(Map:new()), '{}')
  -- table list
  lu.assertEquals(tables.stringify({1, true, "Hi"}), '{1,true,"Hi",}')
  lu.assertEquals(tables.stringify(List:new()), '{}')
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

local function assertSchemaValueTranslated(schema, value, expectedValue)
  lu.assertNil(tables.getSchemaValue(schema, value, false))
  lu.assertEquals(getSchemaValueOrFail(schema, value, true), expectedValue)
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
        type = 'string',
        default = 'Def'
      },
      count = {
        type = 'integer',
        default = 1
      },
      available = {
        type = 'boolean',
        default = false
      },
      s = {
        type = 'string'
      },
      n = {
        type = 'number'
      },
    }
  }
  lu.assertEquals(getSchemaValueOrFail(schema, {name = 'Bag', count = 3, available = true}, true),
    {name = 'Bag', count = 3, available = true})
  lu.assertEquals(getSchemaValueOrFail(schema, {name = 'Tea', count = '2', available = 'false'}, true),
    {name = 'Tea', count = 2, available = false})
  lu.assertEquals(getSchemaValueOrFail(schema, {name = 'Cup'}, true), {name = 'Cup', count = 1, available = false})
  lu.assertEquals(getSchemaValueOrFail(schema, {}, true), {name = 'Def', count = 1, available = false})
end

function Test_getSchemaValue_allOf()
  local s = {allOf = {
    {type = 'string', minLength = 2},
    {type = 'string', maxLength = 5},
  }}
  lu.assertEquals(getSchemaValueOrFail(s, 'good'), 'good')
  lu.assertNil(tables.getSchemaValue(s, 's'))
  lu.assertNil(tables.getSchemaValue(s, 'too long'))
end

function Test_getSchemaValue_anyOf()
  local s = {anyOf = {
    {type = 'string', minLength = 2, maxLength = 5},
    {type = 'string', minLength = 6, maxLength = 12},
    {type = 'string', minLength = 4, maxLength = 8},
  }}
  lu.assertEquals(getSchemaValueOrFail(s, 'short'), 'short')
  lu.assertEquals(getSchemaValueOrFail(s, 'quite long'), 'quite long')
  lu.assertNil(tables.getSchemaValue(s, 's'))
  lu.assertNil(tables.getSchemaValue(s, 'too long long long'))
end

function Test_getSchemaValue_oneOf()
  local s = {oneOf = {
    {type = 'string', minLength = 2, maxLength = 5},
    {type = 'string', minLength = 6, maxLength = 12},
    {type = 'string', minLength = 4, maxLength = 8},
  }}
  lu.assertEquals(getSchemaValueOrFail(s, 'abc'), 'abc')
  lu.assertEquals(getSchemaValueOrFail(s, 'enough long'), 'enough long')
  lu.assertNil(tables.getSchemaValue(s, 's'))
  lu.assertNil(tables.getSchemaValue(s, 'short'))
  lu.assertNil(tables.getSchemaValue(s, 'too long long long'))
end

function Test_getSchemaValue_not()
  local s = {type = 'string', ['not'] = {type = 'string', minLength = 2, maxLength = 5}}
  lu.assertEquals(getSchemaValueOrFail(s, 's'), 's')
  lu.assertEquals(getSchemaValueOrFail(s, 'enough long'), 'enough long')
  lu.assertNil(tables.getSchemaValue(s, 'short'))
end

function Test_getSchemaValue_ref()
  local schema = {
    type = 'object',
    properties = {
      name = { ['$ref'] = '#/$defs/ref1' },
      truc = { ['$ref'] = '#/$defs/ref2' },
    },
    ['$defs'] = {
      ref1 = {
        type = 'string',
        default = 'Def'
      },
      ref2 = {
        type = 'object',
        properties = {
          count = {
            type = 'integer',
            default = 1
          },
          available = {
            type = 'boolean',
            default = false
          }
        }
      }
    }
  }
  lu.assertEquals(getSchemaValueOrFail(schema, {name = 'Bag', truc = {count = 3, available = true}}, true),
    {name = 'Bag', truc = {count = 3, available = true}})
  lu.assertEquals(getSchemaValueOrFail(schema, {name = 'Tea', truc = {count = '2', available = 'false'}}, true),
    {name = 'Tea', truc = {count = 2, available = false}})
  lu.assertEquals(getSchemaValueOrFail(schema, {name = 'Cup'}, true), {name = 'Cup', truc = {count = 1, available = false}})
  lu.assertEquals(getSchemaValueOrFail(schema, {}, true), {name = 'Def', truc = {count = 1, available = false}})
end

function Test_createArgumentTableWithCommas()
  local arguments = {'-h', '-x', 'y', '-u', '---v', 'w'}
  local t = tables.createArgumentTable(arguments)
  lu.assertEquals(tables.getArgument(t, 'x'), 'y')
  lu.assertEquals(tables.getArgument(t, 'u'), '-v')
  lu.assertNil(tables.getArgument(t, 'v'))
  lu.assertNil(tables.getArgument(t, 't'))
  lu.assertNotNil(tables.getArgument(t, 'h'))
end

function Test_createArgumentTable()
  local arguments = {'-h', '-x', 'y', '-u', 'v', 'w'}
  local t = tables.createArgumentTable(arguments)
  lu.assertEquals(tables.getArgument(t, 'x'), 'y')
  lu.assertEquals(tables.getArgument(t, 'u'), 'v')
  lu.assertNil(tables.getArgument(t, 't'))
  lu.assertNotNil(tables.getArgument(t, 'h'))
end

function Test_createArgumentTableWithRmptyPath()
  local arguments = {'-h', '-x', 'y', 'v', 'w'}
  local t = tables.createArgumentTable(arguments)
  lu.assertEquals(t, {h=true, ['0']={'v', 'w'}, x='y'})
  local t = tables.createArgumentTable(arguments, {emptyPath = 'u'})
  lu.assertEquals(t, {h=true, u={'v', 'w'}, x='y'})
end

function Test_createArgumentTablePath()
  local arguments = {'-h', '-x', 'y', '-a.b', 'v', '-a.c', 'u', 'v', '-a.e', 'u', '-a.e', 'v'}
  local t = tables.createArgumentTable(arguments, {
    defaultValues = {a = {c = 'ww', d = 'x'}}
  })
  --print(tables.stringify(t, 2))
  lu.assertEquals(tables.getArgument(t, 'x'), 'y')
  lu.assertEquals(tables.getArgument(t, 'a.b'), 'v')
  lu.assertEquals(tables.getArgument(t, 'a.c'), 'u')
  lu.assertEquals(tables.getArgument(t, 'a.d'), 'x')
  lu.assertEquals(t['0'], 'v')
  lu.assertEquals(t.a.e, {'u', 'v'})
  lu.assertNil(tables.getArgument(t, 't'))
  lu.assertNotNil(tables.getArgument(t, 'h'))
end

os.exit(lu.LuaUnit.run())
