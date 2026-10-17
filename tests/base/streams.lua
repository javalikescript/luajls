local lu = require('luaunit')

local StreamHandler = require('jls.io.StreamHandler')
local BufferedStreamHandler = require('jls.io.streams.BufferedStreamHandler')
local ChunkedStreamHandler = require('jls.io.streams.ChunkedStreamHandler')
local BlockStreamHandler = require('jls.io.streams.BlockStreamHandler')
local RangeStreamHandler = require('jls.io.streams.RangeStreamHandler')
local DelayedStreamHandler = require('jls.io.streams.DelayedStreamHandler')
local LimitedStreamHandler = require('jls.io.streams.LimitedStreamHandler')
local PromiseStreamHandler = require('jls.io.streams.PromiseStreamHandler')
local PromisesStreamHandler = require('jls.io.streams.PromisesStreamHandler')
local Promise = require('jls.lang.Promise')

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

local function createCapturedStreamHandler()
  local captured = {data_list = {}, error_list = {}}
  local handler = StreamHandler:new(function(_, data)
    table.insert(captured.data_list, data ~= nil and data)
  end, function(_, err)
    table.insert(captured.error_list, err ~= nil and err)
  end)
  return captured, handler
end

local function capture(promise)
  local result = {}
  promise:next(function(value)
    result.resolved = true
    result.value = value
  end, function(err)
    result.failed = true
    result.error = err
  end)
  return result
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
  assertCaptureStreamHandler(cs)
  s:onData('Hello')
  assertCaptureStreamHandler(cs)
  s:onData(' world !')
  assertCaptureStreamHandler(cs)
  s:onData()
  assertCaptureStreamHandler(cs, {'Hello world !', false})
end

function Test_limited()
  local cs = createCaptureStreamHandler()
  local s = RangeStreamHandler:new(cs, 0, 10)
  assertCaptureStreamHandler(cs)
  s:onData('Hello')
  assertCaptureStreamHandler(cs, {'Hello'})
  s:onData(' world !')
  assertThenCleanCaptureStreamHandler(cs, {'Hello', ' worl', false})
  s = RangeStreamHandler:new(cs, 0, 100)
  endData(s, 'Hello world !')
  assertThenCleanCaptureStreamHandler(cs, {'Hello world !', false})
  s = RangeStreamHandler:new(cs, 0, 5)
  endData(s, 'Hello')
  assertThenCleanCaptureStreamHandler(cs, {'Hello', false})
end

function Test_chunked()
  local cs = createCaptureStreamHandler()
  local s = ChunkedStreamHandler:new(cs, '\n', true)
  assertCaptureStreamHandler(cs)
  s:onData('Hello')
  assertCaptureStreamHandler(cs)
  s:onData(' world !\n')
  assertCaptureStreamHandler(cs, {'Hello world !'})
  s:onData('Hi\nBonjour\n')
  assertCaptureStreamHandler(cs, {'Hello world !', 'Hi', 'Bonjour'})
  s:onData()
  assertCaptureStreamHandler(cs, {'Hello world !', 'Hi', 'Bonjour', false})
end

function Test_tee()
  local cs1 = createCaptureStreamHandler()
  local cs2 = createCaptureStreamHandler()
  local s = StreamHandler.tee(cs1, cs2)
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

function Test_tee_promise()
  local ps = StreamHandler:new(function(_, data)
    return Promise.resolve(data)
  end)
  local id = StreamHandler:new(function(_, data)
    return data
  end)
  lu.assertTrue(Promise:isInstance(StreamHandler.tee(ps, id):onData('Hi')))
  lu.assertTrue(Promise:isInstance(StreamHandler.tee(id, ps):onData('Hi')))
  lu.assertTrue(Promise:isInstance(StreamHandler.tee(ps, ps):onData('Hi')))
  lu.assertEquals(type(StreamHandler.tee(StreamHandler.null, id):onData('Hi')), 'string')
  lu.assertEquals(type(StreamHandler.tee(id, StreamHandler.null):onData('Hi')), 'string')
end

function Test_keep()
  local cs = createCaptureStreamHandler()
  local s = StreamHandler.keep(cs)
  assertCaptureStreamHandler(cs)
  s:onData('Hi')
  s:onData('!')
  s:onData()
  s:onData('Bye')
  assertCaptureStreamHandler(cs, {'Hi', '!'})
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

function Test_ensureCallback()
  local fn = function() end
  lu.assertFalse(pcall(StreamHandler.ensureCallback))
  lu.assertFalse(pcall(StreamHandler.ensureCallback, ''))
  lu.assertIsNil(StreamHandler.ensureCallback(nil, true))
  lu.assertIs(StreamHandler.ensureCallback(fn), fn)
  lu.assertEquals(type(StreamHandler.ensureCallback(StreamHandler.null)), 'function')
end

function Test_ensureStreamHandler()
  local fn = function() end
  lu.assertFalse(pcall(StreamHandler.ensureStreamHandler))
  lu.assertFalse(pcall(StreamHandler.ensureStreamHandler, ''))
  lu.assertIs(StreamHandler.ensureStreamHandler(StreamHandler.null), StreamHandler.null)
  lu.assertTrue(StreamHandler:isInstance(StreamHandler.ensureStreamHandler(fn)))
end

function Test_fill()
  local cs = createCaptureStreamHandler()
  StreamHandler.fill(cs, 'Hi')
  assertCaptureStreamHandler(cs, {'Hi', false})
  local ps = StreamHandler:new(function(_, data)
    return Promise.resolve(data)
  end)
  lu.assertTrue(Promise:isInstance(StreamHandler.fill(ps, 'Hi')))
end

function Test_delayed_initial_state()
  local s = DelayedStreamHandler:new()
  lu.assertIsFalse(s:isEnded())
  lu.assertIsFalse(s:isClosed())
  lu.assertIsNil(s:getError())
  lu.assertNotNil(s:getStringBuffer())
  lu.assertEquals(s:getBuffer(), '')
end

function Test_delayed_buffer()
  local s = DelayedStreamHandler:new()
  s:onData('Hello')
  s:onData(' world')
  lu.assertIsFalse(s:isEnded())
  lu.assertEquals(s:getBuffer(), 'Hello world')
  local captured, handler = createCapturedStreamHandler()
  s:setStreamHandler(handler)
  lu.assertIs(s:getStreamHandler(), handler)
  lu.assertEquals(captured.data_list, {'Hello world'})
  lu.assertIsNil(s:getStringBuffer())
end

function Test_delayed_end()
  local s = DelayedStreamHandler:new()
  s:onData('Hello')
  s:onData()
  lu.assertTrue(s:isEnded())
  local captured, handler = createCapturedStreamHandler()
  s:setStreamHandler(handler)
  lu.assertEquals(captured.data_list, {'Hello', false})
end

function Test_delayed_error()
  local s = DelayedStreamHandler:new()
  s:onData('Hello')
  s:onError('Ooops')
  lu.assertTrue(s:isEnded())
  lu.assertEquals(s:getError(), 'Ooops')
  local captured, handler = createCapturedStreamHandler()
  s:setStreamHandler(handler)
  lu.assertEquals(captured.error_list, {'Ooops'})
end

function Test_delayed_close()
  local s = DelayedStreamHandler:new()
  s:close()
  lu.assertTrue(s:isClosed())
  local closed = false
  local handler = StreamHandler:new(function() end)
  handler.close = function() closed = true end
  s:setStreamHandler(handler)
  lu.assertTrue(closed)
end

function Test_delayed_direct()
  local captured, handler = createCapturedStreamHandler()
  local s = DelayedStreamHandler:new()
  s:setStreamHandler(handler)
  s:onData('Hi')
  lu.assertEquals(captured.data_list, {'Hi'})
  s:onData()
  lu.assertEquals(captured.data_list, {'Hi', false})
end

function Test_limited_basic()
  local captured, handler = createCapturedStreamHandler()
  local s = LimitedStreamHandler:new(handler, 10, 0)
  lu.assertIs(s:getStreamHandler(), handler)
  lu.assertEquals(captured.data_list, {})
  s:onData('Hello')
  lu.assertEquals(captured.data_list, {'Hello'})
  s:onData(' world !')
  lu.assertEquals(captured.data_list, {'Hello', ' worl', false})
end

function Test_limited_offset()
  local captured, handler = createCapturedStreamHandler()
  local s = LimitedStreamHandler:new(handler, 5, 2)
  lu.assertEquals(captured.data_list, {})
  s:onData('Hello world !')
  lu.assertEquals(captured.data_list, {'llo w', false})
end

function Test_limited_full()
  local captured, handler = createCapturedStreamHandler()
  local s = LimitedStreamHandler:new(handler, 100, 0)
  s:onData('Hello world !')
  s:onData()
  lu.assertEquals(captured.data_list, {'Hello world !', false})
end

function Test_limited_empty()
  local captured, handler = createCapturedStreamHandler()
  local s = LimitedStreamHandler:new(handler, 5, 0)
  s:onData()
  lu.assertEquals(captured.data_list, {false})
end

function Test_promise_pending()
  local captured, handler = createCapturedStreamHandler()
  local s = PromiseStreamHandler:new(handler)
  local result = capture(s:getPromise())
  lu.assertIsNil(result.resolved)
  lu.assertIsNil(result.failed)
  s:onData('Hello')
  lu.assertIsNil(result.resolved)
  lu.assertEquals(captured.data_list, {'Hello'})
end

function Test_promise_resolves_with_size()
  local captured, handler = createCapturedStreamHandler()
  local s = PromiseStreamHandler:new(handler)
  local result = capture(s:getPromise())
  s:onData('Hello')
  s:onData('Hi')
  s:onData()
  lu.assertTrue(result.resolved)
  lu.assertEquals(result.value, 7)
  lu.assertEquals(captured.data_list, {'Hello', 'Hi', false})
end

function Test_promise_handler_promise()
  local handler = StreamHandler:new(function(_, data)
    return Promise.resolve(data)
  end)
  local s = PromiseStreamHandler:new(handler)
  local result = capture(s:getPromise())
  s:onData('Hello')
  lu.assertIsNil(result.resolved)
  s:onData()
  lu.assertTrue(result.resolved)
  lu.assertEquals(result.value, 5)
end

function Test_promise_error()
  local captured, handler = createCapturedStreamHandler()
  local s = PromiseStreamHandler:new(handler)
  local result = capture(s:getPromise())
  s:onError('Ooops')
  lu.assertTrue(result.failed)
  lu.assertEquals(result.error, 'Ooops')
  lu.assertEquals(captured.error_list, {'Ooops'})
end

function Test_promise_close()
  local s = PromiseStreamHandler:new(StreamHandler:new(function() end))
  local result = capture(s:getPromise())
  s:close()
  lu.assertTrue(result.failed)
  lu.assertEquals(result.error, 'Closed')
end

function Test_promise_reset()
  local s = PromiseStreamHandler:new(StreamHandler:new(function() end))
  local result = capture(s:getPromise())
  s:onData('Hi')
  s:onData()
  lu.assertEquals(result.value, 2)
  s:reset()
  local newResult = capture(s:getPromise())
  lu.assertIsNil(newResult.resolved)
  lu.assertIsNil(newResult.failed)
end

function Test_read_then_onData()
  local s = PromisesStreamHandler:new()
  lu.assertFalse(s:available())
  local result = capture(s:read())
  lu.assertFalse(s:available())
  s:onData('Hello')
  lu.assertTrue(result.resolved)
  lu.assertEquals(result.value, 'Hello')
  lu.assertFalse(s:available())
end

function Test_onData_then_read()
  local s = PromisesStreamHandler:new()
  s:onData('Hi')
  lu.assertTrue(s:available())
  local result = capture(s:read())
  lu.assertEquals(result.value, 'Hi')
  lu.assertFalse(s:available())
end

function Test_read_seq()
  local s = PromisesStreamHandler:new()
  local r1 = capture(s:read())
  local r2 = capture(s:read())
  s:onData('a')
  s:onData('b')
  lu.assertEquals(r1.value, 'a')
  lu.assertEquals(r2.value, 'b')
end

function Test_end()
  local s = PromisesStreamHandler:new()
  s:onData('a')
  s:onData()
  local r1 = capture(s:read())
  lu.assertEquals(r1.value, 'a')
  local r2 = capture(s:read())
  lu.assertTrue(r2.resolved)
  lu.assertIsNil(r2.value)
  local r3 = capture(s:read())
  lu.assertTrue(r3.failed)
  lu.assertEquals(r3.error, 'ended')
end

function Test_end_pending()
  local s = PromisesStreamHandler:new()
  local r1 = capture(s:read())
  s:onData()
  lu.assertTrue(r1.resolved)
  lu.assertIsNil(r1.value)
  local r2 = capture(s:read())
  lu.assertTrue(r2.failed)
  lu.assertEquals(r2.error, 'ended')
end

function Test_error()
  local s = PromisesStreamHandler:new()
  local result = capture(s:read())
  s:onError('Ooops')
  lu.assertTrue(result.failed)
  lu.assertEquals(result.error, 'Ooops')
end

function Test_close()
  local s = PromisesStreamHandler:new()
  s:close()
  local result = capture(s:read())
  lu.assertTrue(result.failed)
  lu.assertEquals(result.error, 'closed')
end

os.exit(lu.LuaUnit.run())
