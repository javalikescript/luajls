-- For compatibility, to remove

local StreamHandler = require('jls.io.streams.StreamHandler')

return {
  StreamHandler = StreamHandler,
  CallbackStreamHandler = StreamHandler.CallbackStreamHandler,
  BufferedStreamHandler = require('jls.io.streams.BufferedStreamHandler'),
  LimitedStreamHandler = require('jls.io.streams.LimitedStreamHandler'),
  ChunkedStreamHandler = require('jls.io.streams.ChunkedStreamHandler'),
  ensureCallback = StreamHandler.ensureCallback,
  ensureStreamHandler = StreamHandler.ensureStreamHandler
}