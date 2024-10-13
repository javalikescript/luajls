local lu = require('luaunit')

local class = require('jls.lang.class')
local serialization = require('jls.lang.serialization')

function Test_serialize_instance()
  local Account = class.create(function(account)
    function account:initialize(a, b)
      self.a = a
      self.b = b
    end
    function account:serialize()
      return serialization.serialize(self.a, self.b)
    end
    function account:deserialize(s)
      self.a, self.b = serialization.deserialize(s, 'string', 'number|nil')
    end
  end)
  package.loaded['tests.Account'] = Account
  local anAccount = Account:new('Hello', 123)
  local sdAccount = serialization.deserialize(serialization.serialize(anAccount), 'tests.Account')
  lu.assertEquals(sdAccount.a, 'Hello')
  lu.assertEquals(sdAccount.b, 123)
end

local function assertSerDer(v, ...)
  local r = serialization.deserialize(serialization.serialize(v), ...)
  lu.assertEquals(r, v)
end

function Test_serialize_deserialize()
  local t = {a = 1, b = true, c = 'Hi', d = {da = 2, db = false, dc = 'Hello', dd = {'a', 'b'}}}
  assertSerDer(t, 'table')
  assertSerDer({}, 'table')
  assertSerDer(12345, 'number')
  assertSerDer(1.2345, 'number')
  assertSerDer(true, 'boolean')
  assertSerDer(false, 'boolean')
  assertSerDer('Hello !', 'string')
  assertSerDer('', 'string')
  assertSerDer('\026Hi', 'string')
  assertSerDer('a\0b', 'string')
  assertSerDer(nil, 'string|nil')
  assertSerDer(nil, 'nil')
end

function Test_serialize_string()
  local s = 'Hello'
  local ss = serialization.serialize(s)
  lu.assertEquals(ss, s)
  local r = serialization.deserialize(ss, 'string')
  lu.assertEquals(r, s)
end

-- TODO Check this
-- lua -e "for i=1,2 do local v; if i==1 then; v="Yo"; print('assign', v); end; print(i, v); end"

os.exit(lu.LuaUnit.run())
