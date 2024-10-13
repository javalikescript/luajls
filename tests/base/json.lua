local lu = require('luaunit')

local loader = require('jls.lang.loader')
local json = require('jls.util.json')
local Map = require('jls.util.Map')
local List = require('jls.util.List')
local cjson = package.loaded['cjson']

function Test_decode()
  local t = json.decode('{"aString": "Hello world !", "anInteger": 123, "aNumber": 1.23, "aBoolean": true, "aNull": null}')
  lu.assertEquals(t.aString, 'Hello world !')
  lu.assertEquals(t.anInteger, 123)
  lu.assertEquals(t.aNumber, 1.23)
  lu.assertEquals(t.aBoolean, true)
end

local function assertEncode(fn)
  lu.assertEquals(fn({aString = 'Hello world !'}), '{"aString":"Hello world !"}')
  lu.assertEquals(fn({anInteger = 123}), '{"anInteger":123}')
  lu.assertEquals(fn({aNumber = 1.23}), '{"aNumber":1.23}')
  lu.assertEquals(fn({aBoolean = true}), '{"aBoolean":true}')
  lu.assertEquals(fn({1, 2, 3}), '[1,2,3]')
end

function Test_encode()
  assertEncode(json.encode)
end

function Test_stringify()
  assertEncode(json.stringify)
  lu.assertEquals(json.stringify('a\r\nb "Hi" 1/2'), '"a\\r\\nb \\"Hi\\" 1/2"')
  lu.assertEquals(json.stringify(json.null), 'null')
  lu.assertEquals(json.stringify(nil), 'null')
end

function Test_stringify_lenient()
  local f = function() end
  local u = io.stdout
  local t = {a = 1, f = f, u = u, z = 'z'}
  t.t = t
  local l = {1, f, nil, u, 'z'}
  l[3] = l
  local tt = {a = 1, [f] = 2, [u] = 3, z = 'z'}
  lu.assertEquals(json.stringify(f, nil, true), 'null')
  lu.assertEquals(json.stringify(u, nil, true), 'null')
  lu.assertEquals(json.stringify(t, nil, true), '{"a":1,"f":null,"t":null,"u":null,"z":"z"}')
  lu.assertEquals(json.stringify(l, nil, true), '[1,null,null,null,"z"]')
  lu.assertEquals(json.stringify(tt, nil, true), '{"a":1,"z":"z"}')
end

function Test_list_with_hole()
  lu.assertFalse(pcall(json.stringify, {1, nil, 3}))
  lu.assertEquals(json.stringify({1, json.null, 3}), '[1,null,3]')
  lu.assertEquals(json.decode('[1,null,3]'), {1, json.null, 3})
end

function Test_stringify_empty_table()
  lu.assertEquals(json.stringify({}), '{}') -- unspecified
  lu.assertEquals(json.stringify({n = 0}), '[]') -- may conflict with a map
  lu.assertEquals(json.stringify(List:new()), '[]')
  lu.assertEquals(json.stringify(Map:new()), '{}')
end

function Test_stringify_mixed_table()
  lu.assertFalse(pcall(json.stringify, {[1] = 1, ['2'] = 2}))
  lu.assertFalse(pcall(json.stringify, {[1] = 1, ['1'] = 2}))
end

function Test_unicode()
  lu.assertEquals(json.stringify('\u{0135}'), '"\u{0135}"')
  lu.assertEquals(json.encode('\u{0135}'), '"\u{0135}"')
end

if cjson then

  function Test_cjson_mixed_table()
    -- cjson does not protect against mixed content
    lu.assertStrMatches(cjson.encode({[1] = 1, ['1'] = 2}), '{"1":[12],"1":[12]}')
    -- cjson overwrites with the last entry
    lu.assertEquals(cjson.decode('{"1":1,"1":2}'), {['1'] = 2})
  end

  function Test_encode_decode_sparse_array()
    lu.assertFalse(pcall(json.encode, {1, nil, 3}))
  end

end

local function normalize(s)
  return string.gsub(string.gsub(s, '\r\n', '\n'), '%]EOF$', ']')
end

function Test_stringify_2()
  lu.assertEquals(json.stringify({a = 1, b = 'Hi', c = false}, 2), normalize([[{
  "a": 1,
  "b": "Hi",
  "c": false
}]]))
  lu.assertEquals(json.stringify({3, 'Hi', 1, 2}, 2), normalize([[[
  3,
  "Hi",
  1,
  2
]EOF]]))
  lu.assertEquals(json.stringify({a = 1, b = 'Hi', c = false, d = {a = 2.34, b = '"hello"', c = true}}, 2), normalize([[{
  "a": 1,
  "b": "Hi",
  "c": false,
  "d": {
    "a": 2.34,
    "b": "\"hello\"",
    "c": true
  }
}]]))
end

function Test_decode_encode()
  -- leading null values are not supported by dkjson
  local s = '["Hello world !",123,1.23,true,null,false]'
  local ds = json.decode(s)
  lu.assertEquals(json.encode(ds), s)
end

local function assertEncodeDecode(t)
  lu.assertEquals(json.decode(json.encode(t)), t)
end

function Test_encode_decode()
  assertEncodeDecode({
    aString = 'Hello world !',
    anInteger = 123,
    aNumber = 1.23,
    aBoolean = true
  })
  assertEncodeDecode({'Hello world !', 123, 1.23, true})
end

function Test_stringify_parse()
  local l = {
    'Hello world !', 123, 1.23, true,
    {},
    {aString = 'Hello world !', anInteger = 123, aNumber = 1.23, aBoolean = true},
    {
      a = {aString = 'Hello world !', anInteger = 123, aNumber = 1.23, aBoolean = true},
      b = {aString = 'Hi', anInteger = 321, aNumber = 3.21, aBoolean = false},
    },
  }
  for _, e in ipairs(l) do
    lu.assertEquals(json.parse(json.stringify(e)), e)
  end
end

function Test_stringify_parse()
  local s = '["Hello world !",123,1.23,true,null,false]'
  lu.assertEquals(json.stringify(json.parse(s)), s)
end

function Test_require()
  loader.addLuaPath('?.lua')
  lu.assertEquals(json.require('tests/res_test.json'), {a = 'Hi', b = 1})
  lu.assertNil(json.require('tests/not_a_file.json', true))
  loader.resetLuaPath()
end

os.exit(lu.LuaUnit.run())
