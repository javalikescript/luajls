local lu = require('luaunit')

local EventPublisher = require("jls.util.EventPublisher")

function test_subscribe_publish()
    local v = 0
    local ep = EventPublisher:new()
    ep:publishEvent('test')
    lu.assertEquals(v, 0)
    ep:subscribeEvent('test', function()
      v = v + 1
    end)
    lu.assertEquals(v, 0)
    ep:publishEvent('test')
    lu.assertEquals(v, 1)
    ep:publishEvent('test')
    lu.assertEquals(v, 2)
end

function test_subscribe_publish_args()
  local v = 0
  local va = nil
  local ep = EventPublisher:new()
  ep:publishEvent('test')
  lu.assertEquals(v, 0)
  ep:subscribeEvent('test', function(a)
    v = v + 1
    va = a
  end)
  lu.assertEquals(v, 0)
  lu.assertEquals(va, nil)
  ep:publishEvent('test')
  lu.assertEquals(v, 1)
  lu.assertEquals(va, nil)
  ep:publishEvent('test', 'Hi')
  lu.assertEquals(v, 2)
  lu.assertEquals(va, 'Hi')
end

function test_subscribes_publish()
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

function test_unsubscribe()
  local v = 0
  local ep = EventPublisher:new()
  local eventFn = ep:subscribeEvent('test', function()
    v = v + 1
  end)
  ep:publishEvent('test')
  lu.assertEquals(v, 1)
  ep:unsubscribeEvent('test', eventFn)
  ep:publishEvent('test')
  lu.assertEquals(v, 1)
end

function test_unsubscribeAllEvents()
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
