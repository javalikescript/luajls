local lu = require('luaunit')

local class = require('jls.lang.class')
local serialization = require('jls.lang.serialization')

function Test_packv()
  lu.assertEquals(serialization.packv(0), '\x00')
  lu.assertEquals(serialization.packv(1), '\x01')
  lu.assertEquals(serialization.packv(128), '\x80\x01')
  lu.assertEquals(serialization.packv(130), '\x82\x01')
end

function Test_unpackv()
  lu.assertEquals(serialization.unpackv('\x00'), 0)
  lu.assertEquals(serialization.unpackv('\x01'), 1)
  lu.assertEquals(serialization.unpackv('\x80\x01'), 128)
  lu.assertEquals(serialization.unpackv('\x82\x01'), 130)
end

function Test_packv_unpackv()
  for _, i in ipairs({0, 1, 2, 100, 127, 128, 200, 256, 300, 1234, 12345, 123456789}) do
    lu.assertEquals(serialization.unpackv(serialization.packv(i)), i)
  end
end

local function assertSerDer(v, ...)
  local s = serialization.serialize(v)
  --print('serialize size', #s, 'stringify', #(require('jls.util.tables').stringify(v)))
  local r = serialization.deserialize(s, ...)
  lu.assertEquals(r, v)
end

function Test_serialize_deserialize()
  assertSerDer(0, 'number')
  assertSerDer(1, 'number')
  assertSerDer(0.1, 'number')
  assertSerDer(-1, 'number')
  assertSerDer(-0.1, 'number')
  assertSerDer(12345, 'number')
  assertSerDer(1.2345, 'number')
  assertSerDer(-12345, 'number')
  assertSerDer(-1.2345, 'number')
  assertSerDer(true, 'boolean')
  assertSerDer(false, 'boolean')
  assertSerDer('Hello !', 'string')
  assertSerDer('', 'string')
  assertSerDer('\026Hi', 'string')
  assertSerDer('a\0b', 'string')
  assertSerDer(nil, 'string|nil')
  assertSerDer(nil, 'nil')
end

local function assertSerDerFailure(v, e, ...)
  local status, r = pcall(serialization.deserialize, serialization.serialize(v), ...)
  lu.assertFalse(status)
  if not string.find(r, e, 1, true) then
    lu.assertEquals(r, e)
  end
end

function Test_serialize_deserialize_failure()
  assertSerDerFailure(0, 'invalid type', 'string')
  assertSerDerFailure('', 'invalid type', 'number|boolean')
end

function Test_serialize_string()
  local s = 'Hello'
  local ss = serialization.serialize(s)
  lu.assertEquals(ss, s)
  local r = serialization.deserialize(ss, 'string')
  lu.assertEquals(r, s)
end

function Test_serialize_deserialize_table()
  assertSerDer({}, 'table')
  assertSerDer({'a', 'b'}, 'table')
  assertSerDer({a = 1, b = 2}, 'table')
  local t = {a = 1, b = true, c = 'Hi', d = {da = 2, db = false, dc = 'Hello', dd = {'a', 'b'}}, e = ''}
  assertSerDer(t, 'table')
end

function Test_serialize_instance()
  local Account = class.create(function(account)
    function account:initialize(a, b)
      self.a = a
      self.b = b
    end
    function account:serialize(write)
      write(self.a)
      write(self.b)
    end
    function account:deserialize(read)
      self.a = read('string')
      self.b = read('number|nil')
    end
  end)
  package.loaded['tests.Account'] = Account
  local anAccount = Account:new('Hello', 123)
  local sdAccount = serialization.deserialize(serialization.serialize(anAccount), 'tests.Account')
  package.loaded['tests.Account'] = nil
  lu.assertEquals(sdAccount.a, 'Hello')
  lu.assertEquals(sdAccount.b, 123)
end

function Test_serializeError()
  local e = 28808
  local se = serialization.serializeError(e)
  local status, r = pcall(serialization.deserialize, se)
  lu.assertEquals(status, false)
  lu.assertEquals(r, e)
end

os.exit(lu.LuaUnit.run())
