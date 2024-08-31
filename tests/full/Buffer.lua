local lu = require('luaunit')

local Buffer = require('jls.lang.Buffer')

function Test_buffer_from_size()
  local buffer = Buffer.allocate(10)
  lu.assertEquals(buffer:length(), 10)
end

function Test_buffer_from_string()
  local buffer = Buffer.allocate('Hello')
  lu.assertEquals(buffer:length(), 5)
  lu.assertEquals(buffer:toString(), 'Hello')
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

function Test_buffer_reference()
  local buffer = Buffer.allocate(10)
  local lb = Buffer.fromReference(buffer:toReference())
  lb:set('Hello')
  lu.assertEquals(lb:get(1, 5), 'Hello')
end

os.exit(lu.LuaUnit.run())
