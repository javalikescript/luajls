local lu = require('luaunit')

local class = require('jls.lang.class')
local Exception = require('jls.lang.Exception')

function Test_new()
  local function function_stack_b(...)
    local e = Exception:new(...)
    return e
  end
  local function function_stack_a(...)
    local e = function_stack_b(...)
    return e
  end
  local e
  e = function_stack_a('msg')
  lu.assertEquals(e:getMessage(), 'msg')
  lu.assertNil(e:getCause())
  lu.assertEquals(e:getName(), 'jls.lang.Exception')
  lu.assertStrContains(e:getStackTrace(), 'function_stack_b')
  lu.assertStrContains(e:getStackTrace(), 'function_stack_a')

  e = function_stack_a('msg', 'cause', 'stack', 'name')
  lu.assertEquals(e:getMessage(), 'msg')
  lu.assertEquals(e:getCause(), 'cause')
  lu.assertEquals(e:getName(), 'name')
  lu.assertEquals(e:getStackTrace(), 'stack')

  e = function_stack_a('msg', nil, 4)
  lu.assertEquals(e:getMessage(), 'msg')
  lu.assertStrContains(e:getStackTrace(), 'function_stack_a')
  lu.assertNotStrContains(e:getStackTrace(), 'function_stack_b')
end

function Test_toString()
  local e = Exception:new('msg e')
  local f = Exception:new('msg f', e)
  lu.assertEquals(e:getMessage(), 'msg e')
  lu.assertEquals(f:getMessage(), 'msg f')
  lu.assertStrContains(e:toString(), 'jls.lang.Exception: msg e')
  local s = f:toString()
  lu.assertStrContains(s, 'msg e')
  lu.assertStrContains(s, 'msg f')
end

function Test_toJSON()
  local e = Exception:new('msg', 'cause', 'stack', 'name')
  lu.assertEquals(e:toJSON(), {
    name = 'name',
    stack = 'stack',
    cause = 'cause',
    message = 'msg',
  })
end

function Test_fromJSON()
  local e = Exception.fromJSON({
    name = 'name',
    stack = 'stack',
    cause = 'cause',
    message = 'msg',
  })
  lu.assertEquals(e:getMessage(), 'msg')
  lu.assertEquals(e:getCause(), 'cause')
  lu.assertEquals(e:getName(), 'name')
  lu.assertEquals(e:getStackTrace(), 'stack')
end

function Test_throw()
  local e = Exception:new('msg', 'cause', 'stack', 'name')
  local status, ee = Exception.pcall(function()
    e:throw()
  end)
  lu.assertFalse(status)
  lu.assertIs(ee, e)

  status, e = Exception.pcall(function()
    Exception.throw('msg', 'cause', 'stack', 'name')
  end)
  lu.assertFalse(status)
  lu.assertEquals(e:getMessage(), 'msg')
  lu.assertEquals(e:getCause(), 'cause')
  lu.assertEquals(e:getName(), 'name')
  lu.assertEquals(e:getStackTrace(), 'stack')
end

function Test_getMessage()
  for _, v in ipairs({1, true, 'Hi', {}}) do
    lu.assertIs(Exception.getMessage(v), v)
  end
  local e = Exception:new('msg')
  lu.assertEquals(e:getMessage(), 'msg')
  lu.assertEquals(Exception.getMessage(e), 'msg')
end

function Test_pcall()
  local status, e
  status, e = Exception.pcall(function()
    return 'ok'
  end)
  lu.assertTrue(status)
  lu.assertEquals(e, 'ok')
  status, e = Exception.pcall(function()
    error('ouch')
  end)
  lu.assertFalse(status)
  --print(e)
  lu.assertEquals(e:getMessage(), 'ouch')
end

function Test_try()
  local r, e
  r, e = Exception.try(function(a)
    return a
  end, 'Hi')
  lu.assertEquals(r, 'Hi')
  r, e = Exception.try(function(a)
    error(a)
  end, 'Hi')
  lu.assertNil(r)
  lu.assertEquals(e:getMessage(), 'Hi')
end

local getWriteReverseRead = require('tests.getWriteReverseRead')

function Test_serialization()
  local e = Exception:new('msg', 'cause', 'stack', 'name')
  local w, rev, r = getWriteReverseRead()
  e:serialize(w)
  rev()
  local ee = class.makeInstance(Exception)
  ee:deserialize(r)
  lu.assertEquals(ee:getMessage(), 'msg')
  lu.assertEquals(ee:getCause(), 'cause')
  lu.assertEquals(ee:getName(), 'name')
  lu.assertEquals(ee:getStackTrace(), 'stack')
end

os.exit(lu.LuaUnit.run())
