-- This class provides a stream handler that wrap a stream handler.
-- @module jls.io.streams.WrappedStreamHandler
-- @pragma nostrip

-- A WrappedStreamHandler class.
-- @type WrappedStreamHandler

-- Creates a wrapped @{StreamHandler}.
-- @tparam[opt] StreamHandler handler the stream handler to wrap
-- @function WrappedStreamHandler:new

return require('jls.io.StreamHandler').WrappedStreamHandler
