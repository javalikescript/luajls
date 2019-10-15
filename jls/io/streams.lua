--[[
Provide stream helper classes and functions.

Streams classes are mainly used by @{jls.net|network} protocols TCP and UDP.

@module jls.io.streams
@pragma nostrip
]]

local StreamHandler = require('jls.io.streams.StreamHandler')
local CallbackStreamHandler = require('jls.io.streams.CallbackStreamHandler')

return {
  StreamHandler = StreamHandler,
  CallbackStreamHandler = CallbackStreamHandler,
  BufferedStreamHandler = require('jls.io.streams.BufferedStreamHandler'),
  LimitedStreamHandler = require('jls.io.streams.LimitedStreamHandler'),
  ChunkedStreamHandler = require('jls.io.streams.ChunkedStreamHandler'),
  ensureCallback = StreamHandler.ensureCallback,
  ensureStreamHandler = CallbackStreamHandler.ensureStreamHandler
}