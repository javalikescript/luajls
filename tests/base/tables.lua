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
  lu.assertIsNil(tables.getPath({a = 'A value'}, 'a/'))
  lu.assertEquals(tables.getPath({a = {b = 'A value'}}, 'a'), {b = 'A value'})
  lu.assertEquals(tables.getPath({a = {b = 'A value'}}, 'a/'), {b = 'A value'})
  lu.assertEquals(tables.getPath({['2'] = 'A value'}, '2'), 'A value')
  lu.assertEquals(tables.getPath({[''] = 'A value'}, '[""]'), 'A value')
  lu.assertEquals(tables.getPath({[2] = 'A value'}, '[2]'), 'A value')
  lu.assertEquals(tables.getPath({[true] = 'A value'}, '[true]'), 'A value')
  lu.assertEquals(tables.getPath({[false] = 'A value'}, '[false]'), 'A value')
  lu.assertEquals(tables.getPath({[0.10] = 'A value'}, '[0.1]'), 'A value')
  lu.assertEquals(tables.getPath({[0.1] = 'A value'}, '[0.1]', '.'), 'A value')
end

function Test_getPath_tree()
  lu.assertEquals(tables.getPath({a = {b = 'A value'}}, 'a/b'), 'A value')
  lu.assertEquals(tables.getPath({a = {b = 'A value'}}, '/a/b'), 'A value')
  lu.assertEquals(tables.getPath({a = {b = 'A value'}}, '/a/["b"]'), 'A value')
  lu.assertEquals(tables.getPath({a = {b = 'A value'}}, "a['b']"), 'A value')
  lu.assertEquals(tables.getPath({a = {b = 'A value'}}, 'a//b'), 'A value')
  lu.assertEquals(tables.getPath({a = {b = 'A value'}}, '//a/b'), 'A value')
end

function Test_getPath_percent()
  lu.assertEquals(tables.getPath({['b/c'] = 'A value'}, 'b%2Fc'), 'A value')
  lu.assertEquals(tables.getPath({['b/c'] = 'A value'}, '["b/c"]'), 'A value')
  lu.assertEquals(tables.getPath({['[1]'] = 'A value'}, '%5b1%5d'), 'A value')
  lu.assertEquals(tables.getPath({['[1]'] = 'A value'}, '["%5b1%5d"]'), 'A value')
  lu.assertEquals(tables.getPath({['%'] = 'A value'}, '%'), 'A value')
  lu.assertEquals(tables.getPath({['%'] = 'A value'}, '%25'), 'A value')
end

function Test_getPath_list()
  lu.assertEquals(tables.getPath({a = {'x', 'y', 'z'}}, 'a[1]'), 'x')
  lu.assertEquals(tables.getPath({a = {'x', 'y', 'z'}}, 'a/[2]'), 'y')
  lu.assertNil(tables.getPath({a = {'x', 'y', 'z'}}, 'a/2'))
  lu.assertEquals(tables.getPath({a = {'x', 'y', 'z'}}, 'a[2]'), 'y')
  lu.assertEquals(tables.getPath({a = {'x', 'y', 'z'}}, 'a[3]'), 'z')
  lu.assertNil(tables.getPath({a = {'x', 'y', 'z'}}, 'a/[4]'))
  lu.assertEquals(tables.getPath({a = {'x', {b = 'A value'}, 'z'}}, 'a[2]/b'), 'A value')
  lu.assertEquals(tables.getPath({a = {'x', {b = 'A value'}, 'z'}}, 'a[2]b'), 'A value')
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
  assertSetPath({}, '/', {a = 'New value'}, {a = 'New value'})
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
  assertSetPath({a = {'x', 'y', 'z'}}, 'a[2]', 'New y', {a = {'x', 'New y', 'z'}})
  assertSetPath({a = {'x', 'y', 'z'}}, 'a/[2]', 'New y', {a = {'x', 'New y', 'z'}})
end

local function assertSetByPath(key)
  lu.assertEquals(tables.setByPath({[key] = {x = 1, y = 2}}, {[key] = {x = 3}}), {[key] = {x = 3, y = 2}})
end

function Test_setByPath()
  assertSetByPath('a')
  assertSetByPath('a/b')
  assertSetByPath('a.b')
  assertSetByPath('a|b')
  assertSetByPath('%')
  assertSetByPath(2)
  assertSetByPath(0.1)
  assertSetByPath(true)
  assertSetByPath(false)
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
  lu.assertEquals(tables.mapValuesByPath({['a'] = 'A value'}), {['/a'] = 'A value'})
  lu.assertEquals(tables.mapValuesByPath({['/'] = 'A value'}), {['/%2F'] = 'A value'})
  lu.assertEquals(tables.mapValuesByPath({[0.1] = 'A value'}), {['/[0.1]'] = 'A value'})
  lu.assertEquals(tables.mapValuesByPath({[true] = 'A value'}), {['/[true]'] = 'A value'})
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
  -- format
  lu.assertEquals(tables.stringify({1}, 2), '{\n  1,\n}')
  lu.assertEquals(tables.stringify({1}, ' '), '{\n 1,\n}')
end

function Test_stringify_lenient()
  local f = function() end
  local u = io.stdout
  local t = {a = 1, f = f, u = u, z = 'z'}
  t.t = t
  local l = {1, f, nil, u, 'z'}
  l[3] = l
  local tt = {a = 1, [f] = 2, [u] = 3, z = 'z'}
  lu.assertEquals(tables.stringify(f, nil, true), 'nil')
  lu.assertEquals(tables.stringify(u, nil, true), 'nil')
  lu.assertEquals(tables.stringify(t, nil, true), '{a=1,f=nil,t={},u=nil,z="z",}')
  lu.assertEquals(tables.stringify(l, nil, true), '{1,nil,{},nil,"z",}')
  lu.assertEquals(tables.stringify(tt, nil, true), '{a=1,z="z",}')
end

local function getSchemaValueOrFail(schema, value, translateValues)
  local result, err = tables.getSchemaValue(schema, value, translateValues)
  if err then
    lu.fail(err)
    return
  end
  return result
end

local function getSchemaValueError(schema, value, populate)
  local result, err = tables.getSchemaValue(schema, value, populate)
  if result or not err then
    lu.fail('error expected')
    return
  end
  return err
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
  getSchemaValueError(schema, {name = {}})
  lu.assertEquals(getSchemaValueOrFail({
    type = 'object',
    properties = {
      props = {
        type = 'object'
      }
    }
  }, {}, true), {})
end

function Test_getSchemaValue_object_additionalProperties()
  local schema = {
    type = 'object',
    additionalProperties = {
      type = 'number'
    }
  }
  lu.assertEquals(getSchemaValueOrFail(schema, {}), {})
  lu.assertEquals(getSchemaValueOrFail(schema, {a = 1}), {a = 1})
  getSchemaValueError(schema, {name = 'one'})
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
  local arguments = {'-h', '-x', 'y', '-a.b', 'v', '-a.c', 'u', 'v', '-a.e', 'u', '-a.e', 'v', '-a.e[3]', 'w'}
  local t = tables.createArgumentTable(arguments, {
    defaultValues = {a = {c = 'ww', d = 'x'}}
  })
  --print(tables.stringify(t, 2))
  lu.assertEquals(tables.getArgument(t, 'x'), 'y')
  lu.assertEquals(tables.getArgument(t, 'a.b'), 'v')
  lu.assertEquals(tables.getArgument(t, 'a.c'), 'u')
  lu.assertEquals(tables.getArgument(t, 'a.d'), 'x')
  lu.assertEquals(t['0'], 'v')
  lu.assertEquals(t.a.e, {'u', 'v', 'w'})
  lu.assertNil(tables.getArgument(t, 't'))
  lu.assertNotNil(tables.getArgument(t, 'h'))
end

function Test_get()
  lu.assertEquals(tables.get({a = {b = 'Hi'}}, 'a', 'b'), 'Hi')
  lu.assertNil(tables.get({a = {b = 'Hi'}}, 'a', 'c'))
end

function Test_set()
  lu.assertEquals(tables.set({a = {b = 'Hi'}}, 'Hello', 'a', 'b'), {a = {b = 'Hello'}})
  lu.assertEquals(tables.set({a = {b = 'Hi'}}, 'Hello', 'a', 'c'), {a = {b = 'Hi', c = 'Hello'}})
  lu.assertEquals(tables.set({}, 'Hello', 'a', 'b'), {a = {b = 'Hello'}})
end

function Test_shallowCopy()
  local t = {r = {}, b = 1, 0}
  local s = tables.shallowCopy(t)
  lu.assertEquals(s, t)
  lu.assertNotIs(s, t)
  lu.assertIs(s.r, t.r)
end

function Test_deepCopy()
  local t = {r = {}, b = 1, 0}
  local s = tables.deepCopy(t)
  lu.assertEquals(s, t)
  lu.assertNotIs(s, t)
  lu.assertNotIs(s.r, t.r)
end

function Test_deepMap()
  local t = {r = {n = 2}, n = 1, 0}
  local s = tables.deepMap(t, function(v)
    return v + 1
  end)
  lu.assertEquals(s, {r = {n = 3}, n = 2, 1})
end

function Test_deepEquals()
  local t = {r = {c = true, false}, b = 1, 'Hi'}
  lu.assertTrue(tables.deepEquals(t, t))
  lu.assertTrue(tables.deepEquals(t, {r = {c = true, false}, b = 1, 'Hi'}))
  lu.assertFalse(tables.deepEquals(t, {r = {c = true}, b = 1, 'Hi'}))
end

function Test_forEach()
  local c = 0
  local t = {r = {n = 2}, n = 1, 3}
  tables.forEach(t, function(v)
    c = c + v
  end)
  lu.assertEquals(c, 6)
end

function Test_getSchemaValue_missingSchema()
  local code
  tables.getSchemaValue(1, 'value', false, function(c)
    code = c
  end)
  lu.assertEquals(code, 'MISSING_SCHEMA')
end

function Test_getSchemaValue_invalidSchemaType()
  lu.assertStrContains(getSchemaValueError({}, 'value'), 'unsupported schema type')
end

function Test_getSchemaValue_defaultValue()
  lu.assertEquals(tables.getSchemaValue({type = 'string', default = 'Def'}, nil, true), 'Def')
  lu.assertNil(tables.getSchemaValue({type = 'string', default = 'Def'}, nil))
  lu.assertEquals(tables.getSchemaValue({type = 'string', const = 'Cst'}, nil, true), 'Cst')
end

function Test_getSchemaValue_objectConstraints()
  local schema = {
    type = 'object',
    minProperties = 1,
    maxProperties = 2,
    additionalProperties = false,
    properties = {
      a = {type = 'string'},
      b = {type = 'string'}
    }
  }
  lu.assertEquals(getSchemaValueOrFail(schema, {a = 'A'}), {a = 'A'})
  getSchemaValueError(schema, {})
  getSchemaValueError(schema, {a = 'A', b = 'B', c = 'C'})
  getSchemaValueError(schema, {a = 'A', c = 'C'})
end

function Test_getSchemaValue_propertyNames()
  local schema = {type = 'object', propertyNames = {pattern = '^[a-z]+$'}}
  lu.assertEquals(getSchemaValueOrFail(schema, {abc = 'A'}), {abc = 'A'})
  getSchemaValueError(schema, {ABC = 'A'})
end

function Test_getSchemaValue_required()
  local schema = {
    type = 'object',
    properties = {a = {type = 'string'}},
    required = {'a'}
  }
  lu.assertEquals(getSchemaValueOrFail(schema, {a = 'A'}), {a = 'A'})
  getSchemaValueError(schema, {})
end

function Test_getSchemaValue_objectPassthrough()
  local value = {a = 1}
  lu.assertIs(tables.getSchemaValue({type = 'object'}, value), value)
  lu.assertEquals(getSchemaValueOrFail({type = 'object', properties = {a = {type = 'string'}}}, {a = 'A', b = 1}),
    {a = 'A', b = 1})
end

function Test_getSchemaValue_objectPopulateConst()
  local schema = {
    type = 'object',
    properties = {
      a = {type = 'string', const = 'X'}
    }
  }
  lu.assertEquals(getSchemaValueOrFail(schema, {}, true), {a = 'X'})
end

function Test_getSchemaValue_array()
  local schema = {type = 'array', items = {type = 'string'}, minItems = 1, maxItems = 2}
  lu.assertEquals(getSchemaValueOrFail(schema, {'A'}), {'A'})
  lu.assertEquals(getSchemaValueOrFail(schema, {'A', 'B'}), {'A', 'B'})
  getSchemaValueError(schema, {})
  getSchemaValueError(schema, {'A', 'B', 'C'})
  getSchemaValueError(schema, {a = 1})
  getSchemaValueError(schema, {1})
end

function Test_getSchemaValue_arrayNoItems()
  lu.assertEquals(getSchemaValueOrFail({type = 'array'}, {1, 'A'}), {1, 'A'})
end

function Test_getSchemaValue_constEnum()
  lu.assertEquals(getSchemaValueOrFail({type = 'string', const = 'A'}, 'A'), 'A')
  getSchemaValueError({type = 'string', const = 'A'}, 'B')
  lu.assertEquals(getSchemaValueOrFail({type = 'string', enum = {'A', 'B'}}, 'B'), 'B')
  getSchemaValueError({type = 'string', enum = {'A', 'B'}}, 'C')
end

function Test_getSchemaValue_stringConstraints()
  local schema = {type = 'string', pattern = '^a+$', minLength = 1, maxLength = 3}
  lu.assertEquals(getSchemaValueOrFail(schema, 'aa'), 'aa')
  getSchemaValueError(schema, 'b')
  getSchemaValueError(schema, 'aaaa')
  getSchemaValueError(schema, '')
end

function Test_getSchemaValue_numberConstraints()
  local schema = {type = 'number', minimum = 0, maximum = 10, multipleOf = 0.5}
  lu.assertEquals(getSchemaValueOrFail(schema, 2.5), 2.5)
  getSchemaValueError(schema, -1)
  getSchemaValueError(schema, 11)
  getSchemaValueError(schema, 0.3)
end

function Test_getSchemaValue_exclusiveConstraints()
  local schema = {type = 'number', exclusiveMinimum = 0, exclusiveMaximum = 10}
  lu.assertEquals(getSchemaValueOrFail(schema, 5), 5)
  getSchemaValueError(schema, 0)
  getSchemaValueError(schema, 10)
end

function Test_getSchemaValue_cannotParse()
  lu.assertStrContains(getSchemaValueError({type = 'number'}, 'abc', true), 'Cannot parse value')
end

function Test_getSchemaValue_oneOfMultipleMatch()
  local schema = {oneOf = {{type = 'string'}, {type = 'string'}}}
  lu.assertStrContains(getSchemaValueError(schema, 'value'), 'Unmatched composition')
end

function Test_getSchemaByPath()
  local schema = {
    type = 'object',
    properties = {
      a = {type = 'object', properties = {b = {type = 'string'}}},
      list = {type = 'array', items = {type = 'number'}}
    }
  }
  lu.assertEquals(tables.getSchemaByPath(schema, 'a/b').type, 'string')
  lu.assertEquals(tables.getSchemaByPath(schema, 'list/0').type, 'number')
  lu.assertNil(tables.getSchemaByPath(schema, 'x'))
end

function Test_mapSchemasByPath()
  local schema = {
    type = 'object',
    allOf = {{type = 'string'}},
    properties = {
      name = {type = 'string'},
      nested = {type = 'object', properties = {count = {type = 'integer'}}},
      list = {type = 'array', items = {type = 'number'}}
    }
  }
  local paths = tables.mapSchemasByPath(schema, '')
  lu.assertEquals(paths[''].type, 'string')
  lu.assertEquals(paths['name'].type, 'string')
  lu.assertNil(paths['nested'])
  lu.assertEquals(paths['nested/count'].type, 'integer')
  lu.assertEquals(paths['list/#'].type, 'number')
end

function Test_parseLoad_error()
  local value, err = tables.parseLoad('{a=')
  lu.assertNil(value)
  lu.assertNotNil(err)
end

function Test_stringify_errors()
  local t = {}
  t.self = t
  lu.assertFalse(pcall(tables.stringify, t))
  lu.assertFalse(pcall(tables.stringify, io.stdout))
end

function Test_deepEquals_false()
  lu.assertFalse(tables.deepEquals({a = 1}, {a = '1'}))
  lu.assertFalse(tables.deepEquals({a = 1}, {a = 2}))
  lu.assertFalse(tables.deepEquals({a = {b = 1}}, {a = {b = 2}}))
  lu.assertFalse(tables.deepEquals({}, {a = 1}))
end

function Test_compare_nested()
  lu.assertEquals(tables.compare({a = {b = 1}}, {a = {b = 2}}), {a = {b = 2}})
  local diff = tables.compare({a = 1, b = 2, c = 3}, {c = 3})
  lu.assertEquals(#diff._deleted, 2)
  local set = {}
  for _, key in ipairs(diff._deleted) do
    set[key] = true
  end
  lu.assertEquals(set, {a = true, b = true})
end

function Test_patch_nested()
  lu.assertEquals(tables.patch({a = {b = 1, c = 2}}, {a = {b = 3}}), {a = {b = 3, c = 2}})
end

function Test_getPath_errors()
  lu.assertFalse(pcall(tables.getPath, {a = {}}, 'a['))
  lu.assertFalse(pcall(tables.getPath, {a = {}}, 'a[]'))
  lu.assertFalse(pcall(tables.getPath, {a = {}}, 'a[b]'))
  lu.assertNil(tables.get({a = 1}, 'a', 'b'))
end

function Test_set_errors()
  lu.assertNil((tables.set({a = 1}, 'value', 'a', 'b')))
  local t = {}
  lu.assertNil(tables.setPath(t, 'a/b', nil))
  lu.assertEquals(t, {})
  lu.assertFalse(pcall(tables.setPath, {}, '/', 'scalar'))
end

function Test_mergePath_create()
  local t = {}
  tables.mergePath(t, 'a/b', {c = 1})
  lu.assertEquals(t, {a = {b = {c = 1}}})
end

function Test_removePath_errors()
  lu.assertNil(tables.removePath({a = 1}, 'a/b'))
end

function Test_mapValuesByPath_invalidKey()
  lu.assertFalse(pcall(tables.mapValuesByPath, {[function() end] = 1}))
end

function Test_mergeValuesByPath_types()
  lu.assertEquals(tables.mergeValuesByPath({a = {b = 1}}, {a = 2}), {['/a'] = {new = 2}, ['/a/b'] = {old = 1}})
  lu.assertEquals(tables.mergeValuesByPath({a = 1}, {a = {b = 2}}), {['/a'] = {old = 1}, ['/a/b'] = {new = 2}})
end

function Test_createArgumentTable_errors()
  lu.assertFalse(pcall(tables.createArgumentTable, {}, {schema = 1}))
  lu.assertFalse(pcall(tables.createArgumentTable, {}, {defaultValues = 1}))
end

function Test_createArgumentTable_multipleValues()
  lu.assertEquals(tables.createArgumentTable({'-a', '1', '-a', '2', '-a', '3'}).a, {'1', '2', '3'})
end

function Test_createArgumentTable_config()
  local t = tables.createArgumentTable({'-c', 'config.json'}, {
    configPath = 'c',
    configLoader = function(path)
      lu.assertEquals(path, 'config.json')
      return {a = 'fromFile'}
    end
  })
  lu.assertEquals(t.a, 'fromFile')
  lu.assertEquals(t.c, 'config.json')
end

function Test_createArgumentTable_configFromDefaults()
  local t = tables.createArgumentTable({}, {
    configPath = 'c',
    defaultValues = {c = 'default.json'},
    configLoader = function(path)
      lu.assertEquals(path, 'default.json')
      return {b = 2}
    end
  })
  lu.assertEquals(t.b, 2)
end

function Test_createArgumentTable_configFromSchema()
  local loaded
  tables.createArgumentTable({}, {
    configPath = 'c',
    schema = {type = 'object', properties = {c = {type = 'string', default = 'schema.json'}}},
    configLoader = function(path)
      loaded = path
      return {c = 'schema.json'}
    end
  })
  lu.assertEquals(loaded, 'schema.json')
end

function Test_createArgumentTable_configErrors()
  lu.assertFalse(pcall(tables.createArgumentTable, {'-c', 'f'}, {configPath = 'c', configLoader = true}))
  local printed, code
  local ok = pcall(tables.createArgumentTable, {'-c', 'f'}, {
    configPath = 'c',
    configLoader = function()
      error('invalid file')
    end,
    println = function(message)
      printed = message
    end,
    exit = function(c)
      code = c
      error('exit')
    end
  })
  lu.assertFalse(ok)
  lu.assertNotNil(printed)
  lu.assertEquals(code, 1)
end

function Test_createArgumentTable_help()
  local lines = {}
  local schema = {
    title = 'My tool',
    description = 'Does things',
    type = 'object',
    properties = {
      name = {type = 'string', title = 'The name', description = 'The person name', default = 'World'},
      level = {type = 'string', enum = {'low', 'high'}}
    }
  }
  local exited
  tables.createArgumentTable({'-h'}, {
    helpPath = 'h',
    help = 'Usage: tool',
    schema = schema,
    defaultValues = {name = 'Default'},
    aliases = {n = 'name'},
    println = function(...)
      lines[#lines + 1] = table.concat({...}, ' ')
    end,
    exit = function(code)
      exited = code
    end
  })
  lu.assertEquals(exited, 0)
  local text = table.concat(lines, '\n')
  lu.assertStrContains(text, 'Usage: tool')
  lu.assertStrContains(text, 'My tool')
  lu.assertStrContains(text, 'Does things')
  lu.assertStrContains(text, 'Arguments:')
  lu.assertStrContains(text, '--name')
  lu.assertStrContains(text, 'defaults to "World"')
  lu.assertStrContains(text, 'The person name')
  lu.assertStrContains(text, 'in |low|high|')
  lu.assertStrContains(text, 'Default values:')
end

function Test_createArgumentTable_logPath()
  local logger = require('jls.lang.logger')
  local before = logger:getConfig()
  local t = tables.createArgumentTable({'-l', 'warn'}, {logPath = 'l'})
  lu.assertNil(t.l)
  lu.assertEquals(logger:getConfig(), 'WARN')
  logger:setConfig(before)
end

function Test_createArgumentTable_schemaError()
  local printed, code
  tables.createArgumentTable({}, {
    schema = {type = 'object', properties = {n = {type = 'integer'}}, required = {'n'}},
    println = function(message)
      printed = message
    end,
    exit = function(c)
      code = c
    end
  })
  lu.assertNotNil(printed)
  lu.assertEquals(code, 22)
end

function Test_getArgument()
  local t = {a = 'A', b = {'B1', 'B2'}, n = 2, flag = true, ['0'] = 'zero'}
  lu.assertEquals(tables.getArgument(t, 'a'), 'A')
  lu.assertEquals(tables.getArgument(t, 'b'), 'B1')
  lu.assertEquals(tables.getArgument(t, 'b', nil, 2), 'B2')
  lu.assertNil(tables.getArgument(t, 'b', nil, 3))
  lu.assertNil(tables.getArgument(t, 'missing'))
  lu.assertEquals(tables.getArgument(t, 'missing', 'def'), 'def')
  lu.assertEquals(tables.getArgument(t, 'n', nil, 1, true), '2')
  lu.assertNil(tables.getArgument(t, 'n', nil, 2))
  lu.assertIsTrue(tables.getArgument(t, 'flag'))
  lu.assertEquals(tables.getArgument(t), 'zero')
end

function Test_getArguments()
  lu.assertEquals(tables.getArguments({}), {})
  lu.assertEquals(tables.getArguments({a = true}, 'a'), {})
  lu.assertEquals(tables.getArguments({a = 'A'}, 'a'), {'A'})
  lu.assertEquals(tables.getArguments({a = {'A', 'B'}}, 'a'), {'A', 'B'})
  lu.assertEquals(tables.getArguments({['0'] = 'zero'}), {'zero'})
end

os.exit(lu.LuaUnit.run())
