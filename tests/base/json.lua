local lu = require('luaunit')

local json = require("jls.util.json")

function Test_decode()
  local t = json.decode('{"aString": "Hello world !", "anInteger": 123, "aNumber": 1.23, "aBoolean": true, "aNull": null}')
  lu.assertEquals(t.aString, 'Hello world !')
  lu.assertEquals(t.anInteger, 123)
  lu.assertEquals(t.aNumber, 1.23)
  lu.assertEquals(t.aBoolean, true)
end

function Test_encode()
  lu.assertEquals(json.encode({aString = 'Hello world !'}), '{"aString":"Hello world !"}')
  lu.assertEquals(json.encode({anInteger = 123}), '{"anInteger":123}')
  lu.assertEquals(json.encode({aNumber = 1.23}), '{"aNumber":1.23}')
  lu.assertEquals(json.encode({aBoolean = true}), '{"aBoolean":true}')
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

os.exit(lu.LuaUnit.run())
