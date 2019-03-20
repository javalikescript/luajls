local lu = require('luaunit')

local streams = require('jls.io.streams')

function test_callback()
  local dataCaptured, errCaptured
  local bsh = streams.CallbackStreamHandler:new(function(err, data)
    dataCaptured = data
    errCaptured = err
  end)
  lu.assertIsNil(dataCaptured)
  lu.assertIsNil(errCaptured)
  bsh:onData('Hello')
  lu.assertEquals(dataCaptured, 'Hello')
  lu.assertIsNil(errCaptured)
  bsh:onError('Ooops')
  lu.assertIsNil(dataCaptured)
  lu.assertEquals(errCaptured, 'Ooops')
end

os.exit(lu.LuaUnit.run())
