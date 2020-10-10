local lu = require('luaunit')

local EventPublisher = require("jls.util.EventPublisher")

function Test_subscribe_publish()
    local v = 0
    local ep = EventPublisher:new()
    lu.assertFalse(ep:publishEvent('test'))
    lu.assertEquals(v, 0)
    ep:subscribeEvent('test', function()
      v = v + 1
    end)
    lu.assertEquals(v, 0)
    lu.assertTrue(ep:publishEvent('test'))
    lu.assertEquals(v, 1)
    lu.assertTrue(ep:publishEvent('test'))
    lu.assertEquals(v, 2)
end

function Test_subscribe_publish_args()
  local v = 0
  local va, vb
  local ep = EventPublisher:new()
  ep:publishEvent('test')
  lu.assertEquals(v, 0)
  ep:subscribeEvent('test', function(a, b)
    v = v + 1
    va = a
    vb = b
  end)
  lu.assertEquals(v, 0)
  lu.assertNil(va)
  lu.assertNil(vb)
  ep:publishEvent('test', 'Hi', 123)
  lu.assertEquals(v, 1)
  lu.assertEquals(va, 'Hi')
  lu.assertEquals(vb, 123)
  ep:publishEvent('test')
  lu.assertEquals(v, 2)
  lu.assertNil(va)
  lu.assertNil(vb)
end

function Test_subscribe_publish_error()
  local capturedError
  local ep = EventPublisher:new()
  ep:subscribeEvent('test', function(a)
    error('Test')
  end)
  lu.assertFalse(pcall(function()
    ep:publishEvent('test')
  end))
  ep:subscribeEvent('error', function(err)
    capturedError = err or true
  end)
  lu.assertNil(capturedError)
  lu.assertTrue(pcall(function()
    ep:publishEvent('test')
  end))
  lu.assertNotNil(capturedError)
end

function Test_subscribes_publish()
  local v = 0
  local ep = EventPublisher:new()
  ep:publishEvent('test')
  lu.assertEquals(v, 0)
  ep:subscribeEvent('test', function()
    v = v + 1
  end)
  ep:subscribeEvent('test', function()
    v = v + 100
  end)
  lu.assertEquals(v, 0)
  ep:publishEvent('test')
  lu.assertEquals(v, 101)
  ep:publishEvent('test')
  lu.assertEquals(v, 202)
end

function Test_unsubscribe()
  local v = 0
  local ep = EventPublisher:new()
  lu.assertFalse(ep:unsubscribeEvent('test', {}))
  local eventFn = ep:subscribeEvent('test', function()
    v = v + 1
  end)
  ep:publishEvent('test')
  lu.assertEquals(v, 1)
  lu.assertTrue(ep:unsubscribeEvent('test', eventFn))
  ep:publishEvent('test')
  lu.assertFalse(ep:unsubscribeEvent('test', eventFn))
  lu.assertEquals(v, 1)
end

function Test_unsubscribeAllEvents()
  local v = 0
  local ep = EventPublisher:new()
  ep:subscribeEvent('test', function()
    v = v + 1
  end)
  ep:publishEvent('test')
  lu.assertEquals(v, 1)
  ep:unsubscribeAllEvents()
  ep:publishEvent('test')
  lu.assertEquals(v, 1)
end

os.exit(lu.LuaUnit.run())
