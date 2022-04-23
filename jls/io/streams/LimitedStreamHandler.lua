return require('jls.lang.class').create('jls.io.streams.RangeStreamHandler', function(limitedStreamHandler, super)
  function limitedStreamHandler:initialize(handler, length, offset)
    super.initialize(self, handler, offset, length)
  end
end)