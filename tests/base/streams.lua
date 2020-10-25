local lu = require('luaunit')

local streams = require('jls.io.streams')

local function assertStreamHandling(s, t)
  lu.assertIsNil(t.dataCaptured)
  lu.assertIsNil(t.errCaptured)
  s:onData('Hello')
  lu.assertEquals(t.dataCaptured, 'Hello')
  lu.assertIsNil(t.errCaptured)
  s:onError('Ooops')
  lu.assertIsNil(t.dataCaptured)
  lu.assertEquals(t.errCaptured, 'Ooops')
end

local function cleanCaptureStreamHandler(cs)
  cs._captured = {data_list = {}, error_list = {}}
  return cs
end

local function createCaptureStreamHandler()
  return cleanCaptureStreamHandler(streams.StreamHandler:new(function(self, data)
    table.insert(self._captured.data_list, data ~= nil and data)
  end, function(self, err)
    table.insert(self._captured.error_list, err ~= nil and err)
  end))
end

function Test_streamHandler()
  local t = {}
  local s = streams.StreamHandler:new(function(_, data)
    t.dataCaptured = data
    t.errCaptured = nil
  end, function(_, err)
    t.dataCaptured = nil
    t.errCaptured = err
  end)
  assertStreamHandling(s, t)
end

function Test_callback()
  local t = {}
  local s = streams.CallbackStreamHandler:new(function(err, data)
    t.dataCaptured = data
    t.errCaptured = err
  end)
  assertStreamHandling(s, t)
end

function Test_buffered()
  local cs = createCaptureStreamHandler()
  local s = streams.BufferedStreamHandler:new(cs)
  lu.assertEquals(cs._captured, {data_list = {}, error_list = {}})
  s:onData('Hello')
  lu.assertEquals(cs._captured, {data_list = {}, error_list = {}})
  s:onData(' world !')
  lu.assertEquals(cs._captured, {data_list = {}, error_list = {}})
  s:onData()
  lu.assertEquals(cs._captured, {data_list = {'Hello world !', false}, error_list = {}})
end

function Test_limited()
  local cs = createCaptureStreamHandler()
  local s = streams.LimitedStreamHandler:new(cs, 10)
  lu.assertEquals(cs._captured, {data_list = {}, error_list = {}})
  s:onData('Hello')
  lu.assertEquals(cs._captured, {data_list = {'Hello'}, error_list = {}})
  s:onData(' world !')
  lu.assertEquals(cs._captured, {data_list = {'Hello', ' worl', false}, error_list = {}})
end

function Test_chunked()
  local cs = createCaptureStreamHandler()
  local s = streams.ChunkedStreamHandler:new(cs, '\n')
  lu.assertEquals(cs._captured, {data_list = {}, error_list = {}})
  s:onData('Hello')
  lu.assertEquals(cs._captured, {data_list = {}, error_list = {}})
  s:onData(' world !\n')
  lu.assertEquals(cs._captured, {data_list = {'Hello world !'}, error_list = {}})
  s:onData('Hi\nBonjour\n')
  lu.assertEquals(cs._captured, {data_list = {'Hello world !', 'Hi', 'Bonjour'}, error_list = {}})
  s:onData()
  lu.assertEquals(cs._captured, {data_list = {'Hello world !', 'Hi', 'Bonjour', false}, error_list = {}})
end

function Test_multiple()
  local cs1 = createCaptureStreamHandler()
  local cs2 = createCaptureStreamHandler()
  local s = streams.StreamHandler.multiple(cs1, cs2)
  lu.assertEquals(cs1._captured, {data_list = {}, error_list = {}})
  lu.assertEquals(cs2._captured, {data_list = {}, error_list = {}})
  s:onData('Hello')
  cs1:onData(' the')
  s:onData(' world !')
  s:onData()
  lu.assertEquals(cs1._captured, {data_list = {'Hello', ' the', ' world !', false}, error_list = {}})
  lu.assertEquals(cs2._captured, {data_list = {'Hello', ' world !', false}, error_list = {}})
  cleanCaptureStreamHandler(cs1)
  cleanCaptureStreamHandler(cs2)
  s:onError('Ouch')
  lu.assertEquals(cs1._captured, {data_list = {}, error_list = {'Ouch'}})
  lu.assertEquals(cs2._captured, {data_list = {}, error_list = {'Ouch'}})
end

os.exit(lu.LuaUnit.run())
