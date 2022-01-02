local lu = require('luaunit')

local json = require('jls.util.json')
local Map = require('jls.util.Map')
local List = require('jls.util.List')

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
end

function Test_stringify_empty_table()
  lu.assertEquals(json.stringify({}), '[]') -- unspecified
  lu.assertEquals(json.stringify(List:new()), '[]')
  lu.assertEquals(json.stringify(Map:new()), '{}')
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

function Test_encode_decode()
  local t = {
    aString = 'Hello world !',
    anInteger = 123,
    aNumber = 1.23,
    aBoolean = true
  }
  lu.assertEquals(json.decode(json.encode(t)), t)
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

os.exit(lu.LuaUnit.run())
