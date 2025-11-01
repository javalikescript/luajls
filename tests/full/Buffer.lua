local lu = require('luaunit')

local Buffer = require('jls.lang.Buffer')
local BufferFile = require('jls.lang.BufferFile')
local BufferView = require('jls.lang.BufferView')
local serialization = require('jls.lang.serialization')

function Test_buffer_allocate()
  local buffer = Buffer.allocate(10)
  lu.assertEquals(buffer:length(), 10)
  buffer = Buffer.allocate('Hello')
  lu.assertEquals(buffer:length(), 5)
  lu.assertEquals(buffer:get(), 'Hello')
  lu.assertFalse(pcall(Buffer.allocate, -1))
  lu.assertFalse(pcall(Buffer.allocate))
  lu.assertFalse(pcall(Buffer.allocate, 1, 'unknown'))
end

local function assertSetGetBytes(buffer)
  buffer:setBytes(1, 11, 12, 13, 14, 15)
  lu.assertEquals({buffer:getBytes(2, 4)}, {12, 13, 14})
end

local function assertSetGet(buffer)
  buffer:set('Hello')
  lu.assertEquals(buffer:get(1, 5), 'Hello')
end

local function assertBuffers(assertFn, size)
  assertFn(Buffer.allocate(size))
  if BufferFile ~= Buffer then
    assertFn(BufferFile.allocate(size))
  end
  assertFn(Buffer.allocate(size + 2):view(2, size + 1))
end

function Test_buffer_bytes()
  assertBuffers(assertSetGetBytes, 5)
end

function Test_buffer_string()
  assertBuffers(assertSetGet, 5)
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
  local vvb = vb:view(2, 4)
  lu.assertEquals(vb:get(), 'Hello')
  lu.assertEquals(vvb:get(), 'ell')
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
