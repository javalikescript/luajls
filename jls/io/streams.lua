-- For compatibility, to remove

local StreamHandler = require('jls.io.streams.StreamHandler')

return {
  StreamHandler = StreamHandler,
  CallbackStreamHandler = StreamHandler,
  BufferedStreamHandler = require('jls.io.streams.BufferedStreamHandler'),
  LimitedStreamHandler = require('jls.lang.class').create('jls.io.streams.RangeStreamHandler', function(limitedStreamHandler, super)
    function limitedStreamHandler:initialize(handler, length, offset)
      super.initialize(self, handler, offset, length)
    end
  end),
  ChunkedStreamHandler = require('jls.io.streams.ChunkedStreamHandler'),
  ensureCallback = StreamHandler.ensureCallback,
  ensureStreamHandler = StreamHandler.ensureStreamHandler
}