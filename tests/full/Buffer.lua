local lu = require('luaunit')

local Buffer = require('jls.lang.Buffer')
local BufferView = require('jls.lang.BufferView')
local serialization = require('jls.lang.serialization')

function Test_buffer_from_size()
  local buffer = Buffer.allocate(10)
  lu.assertEquals(buffer:length(), 10)
end

function Test_buffer_from_string()
  local buffer = Buffer.allocate('Hello')
  lu.assertEquals(buffer:length(), 5)
  lu.assertEquals(buffer:get(), 'Hello')
end

function Test_buffer_bytes()
  local buffer = Buffer.allocate(5)
  buffer:setBytes(1, 11, 12, 13, 14, 15)
  lu.assertEquals({buffer:getBytes(2, 4)}, {12, 13, 14})
end

function Test_buffer_string()
  local buffer = Buffer.allocate(10)
  buffer:set('Hello')
  lu.assertEquals(buffer:get(1, 5), 'Hello')
end

function Test_buffer_serialization()
  local buffer = Buffer.allocate(10)
  local lb = serialization.deserialize(serialization.serialize(buffer))
  lb:set('Hello')
  lu.assertEquals(lb:get(1, 5), 'Hello')
end

function Test_buffer_view()
  local buffer = Buffer.allocate(10)
  buffer:set('          ')
  local vb = buffer:view(3, 7)
  lu.assertEquals(vb:length(), 5)
  lu.assertEquals(vb:get(), '     ')
  vb:set('Hello')
  lu.assertEquals(vb:get(), 'Hello')
  lu.assertEquals(buffer:get(), '  Hello   ')
end

function Test_buffer_view_serialization()
  local buffer = Buffer.allocate(10)
  buffer:set('          ')
  local vb = buffer:view(3, 7)
  vb = serialization.deserialize(serialization.serialize(vb))
  lu.assertTrue(BufferView:isInstance(vb))
  lu.assertEquals(vb:length(), 5)
  lu.assertEquals(vb:get(), '     ')
  vb:set('Hello')
  lu.assertEquals(vb:get(), 'Hello')
  lu.assertEquals(buffer:get(), '  Hello   ')
end

os.exit(lu.LuaUnit.run())
