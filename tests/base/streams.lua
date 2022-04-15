local lu = require('luaunit')

local StreamHandler = require('jls.io.streams.StreamHandler')
local BufferedStreamHandler = require('jls.io.streams.BufferedStreamHandler')
local LimitedStreamHandler = require('jls.io.streams.LimitedStreamHandler')
local ChunkedStreamHandler = require('jls.io.streams.ChunkedStreamHandler')
local BlockStreamHandler = require('jls.io.streams.BlockStreamHandler')
local RangeStreamHandler = require('jls.io.streams.RangeStreamHandler')

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

local function assertCaptureStreamHandler(cs, dl, el)
  lu.assertEquals(cs._captured.data_list, dl or {})
  lu.assertEquals(cs._captured.error_list, el or {})
  return cs
end

local function assertThenCleanCaptureStreamHandler(cs, dl, el)
  assertCaptureStreamHandler(cs, dl, el)
  cleanCaptureStreamHandler(cs)
  return cs
end

local function onData(s, ...)
  for _, d in ipairs({...}) do
    s:onData(d)
  end
end

local function endData(s, ...)
  onData(s, ...)
  s:onData()
end

local function createCaptureStreamHandler()
  return cleanCaptureStreamHandler(StreamHandler:new(function(self, data)
    table.insert(self._captured.data_list, data ~= nil and data)
  end, function(self, err)
    table.insert(self._captured.error_list, err ~= nil and err)
  end))
end

function Test_streamHandler()
  local t = {}
  local s = StreamHandler:new(function(_, data)
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
  local s = StreamHandler:new(function(err, data)
    t.dataCaptured = data
    t.errCaptured = err
  end)
  assertStreamHandling(s, t)
end

function Test_buffered()
  local cs = createCaptureStreamHandler()
  local s = BufferedStreamHandler:new(cs)
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
  local s = LimitedStreamHandler:new(cs, 10)
  lu.assertEquals(cs._captured, {data_list = {}, error_list = {}})
  s:onData('Hello')
  lu.assertEquals(cs._captured, {data_list = {'Hello'}, error_list = {}})
  s:onData(' world !')
  lu.assertEquals(cs._captured, {data_list = {'Hello', ' worl', false}, error_list = {}})
end

function Test_chunked()
  local cs = createCaptureStreamHandler()
  local s = ChunkedStreamHandler:new(cs, '\n')
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
  local s = StreamHandler.multiple(cs1, cs2)
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

function Test_block()
  local cs = createCaptureStreamHandler()
  local s = BlockStreamHandler:new(cs, 4)
  assertCaptureStreamHandler(cs)
  s:onData('Hello world !')
  assertThenCleanCaptureStreamHandler(cs, {'Hell', 'o wo', 'rld '})
  s:onData()
  assertCaptureStreamHandler(cs, {'!', false})
end

function Test_block_multiple()
  local cs = createCaptureStreamHandler()
  local s = BlockStreamHandler:new(cs, 3, true)
  assertCaptureStreamHandler(cs)
  s:onData('Hello ')
  assertThenCleanCaptureStreamHandler(cs, {'Hello '})
  s:onData('wor')
  assertThenCleanCaptureStreamHandler(cs, {'wor'})
  s:onData('ld !')
  assertThenCleanCaptureStreamHandler(cs, {'ld '})
  s:onData()
  assertCaptureStreamHandler(cs, {'!', false})
end

function Test_range()
  local cs = createCaptureStreamHandler()
  local s = RangeStreamHandler:new(cs, 0, 100)
  assertCaptureStreamHandler(cs)
  endData(s, 'Hello world !')
  assertThenCleanCaptureStreamHandler(cs, {'Hello world !', false})

  s = RangeStreamHandler:new(cs, 0, 100)
  endData(s, 'Hell', 'o wo', 'rld ', '!')
  assertThenCleanCaptureStreamHandler(cs, {'Hell', 'o wo', 'rld ', '!', false})

  s = RangeStreamHandler:new(cs, 0, 5)
  assertCaptureStreamHandler(cs)
  endData(s, 'Hello world !')
  assertThenCleanCaptureStreamHandler(cs, {'Hello', false})

  s = RangeStreamHandler:new(cs, 2, 100)
  assertCaptureStreamHandler(cs)
  endData(s, 'Hello world !')
  assertThenCleanCaptureStreamHandler(cs, {'llo world !', false})

  s = RangeStreamHandler:new(cs, 2, 5)
  assertCaptureStreamHandler(cs)
  endData(s, 'Hello world !')
  assertThenCleanCaptureStreamHandler(cs, {'llo w', false})

  s = RangeStreamHandler:new(cs, 1, 100)
  endData(s, 'Hell', 'o wo', 'rld ', '!')
  assertThenCleanCaptureStreamHandler(cs, {'ell', 'o wo', 'rld ', '!', false})

  s = RangeStreamHandler:new(cs, 2, 5)
  assertCaptureStreamHandler(cs)
  endData(s, 'Hell', 'o wo', 'rld ', '!')
  assertThenCleanCaptureStreamHandler(cs, {'ll', 'o w', false})
end

os.exit(lu.LuaUnit.run())
