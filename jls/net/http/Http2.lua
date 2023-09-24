local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local StreamHandler = require('jls.io.StreamHandler')
local ChunkedStreamHandler = require('jls.io.streams.ChunkedStreamHandler')
local Hpack = require('jls.net.http.Hpack')
local HttpMessage = require('jls.net.http.HttpMessage')
local Map = require('jls.util.Map')

--local hex = require('jls.util.Codec').getInstance('hex')
--logger = logger:getClass():new(); logger:setLevel('finer')

local FRAME = {
  DATA = 0,
  HEADERS = 1,
  PRIORITY = 2,
  RST_STREAM = 3,
  SETTINGS = 4,
  PUSH_PROMISE = 5,
  PING = 6,
  GOAWAY = 7,
  WINDOW_UPDATE = 8,
  CONTINUATION = 9
}
local FRAME_BY_TYPE = Map.reverse(FRAME)

local ACK_FLAG = 0x01
local END_STREAM_FLAG = 0x01
local END_HEADERS_FLAG = 0x04
local PADDED_FLAG = 0x08
local PRIORITY_FLAG = 0x20

local SETTINGS = {
  HEADER_TABLE_SIZE = 1, -- initial value is 4096
  ENABLE_PUSH = 2,
  MAX_CONCURRENT_STREAMS = 3, -- recommended >99
  INITIAL_WINDOW_SIZE = 4, -- initial value is 65535
  MAX_FRAME_SIZE = 5, -- initial value is 16384
  MAX_HEADER_LIST_SIZE = 6
}
local SETTINGS_BY_ID = Map.reverse(SETTINGS)

local ERRORS = {
  NO_ERROR = 0x0, -- The associated condition is not a result of an error
  PROTOCOL_ERROR = 0x1, -- The endpoint detected an unspecific protocol error
  INTERNAL_ERROR = 0x2, -- The endpoint encountered an unexpected internal error
  FLOW_CONTROL_ERROR = 0x3, -- The endpoint detected that its peer violated the flow-control protocol
  SETTINGS_TIMEOUT = 0x4, -- The endpoint sent a SETTINGS frame but did not receive a response in a timely manner
  STREAM_CLOSED = 0x5, -- The endpoint received a frame after a stream was half-closed
  FRAME_SIZE_ERROR = 0x6, -- The endpoint received a frame with an invalid size
  REFUSED_STREAM = 0x7, -- The endpoint refused the stream prior to performing any application processing
  CANCEL = 0x8, -- Used by the endpoint to indicate that the stream is no longer needed
  COMPRESSION_ERROR = 0x9, -- The endpoint is unable to maintain the header compression context for the connection
  CONNECT_ERROR = 0xa, -- The connection established in response to a CONNECT request was reset or abnormally closed
  ENHANCE_YOUR_CALM = 0xb, -- The endpoint detected that its peer is exhibiting a behavior that might be generating excessive load
  INADEQUATE_SECURITY = 0xc, -- The underlying transport has properties that do not meet minimum security requirements
  HTTP_1_1_REQUIRED = 0xd, -- The endpoint requires that HTTP/1.1 be used instead of HTTP/2
}
local ERRORS_BY_ID = Map.reverse(ERRORS)

local CONNECTION_PREFACE = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

local STATE = {
  IDLE = 0,
  RESERVED = 1, -- promised by sending a PUSH_PROMISE
  OPEN = 2,
  HALF_CLOSED = 3,
  CLOSED = 4,
}

local function findFrame(stream, data, length)
  if stream.preface == nil then
    if length < #CONNECTION_PREFACE then
      return nil
    end
    if string.sub(data, 1, #CONNECTION_PREFACE) == CONNECTION_PREFACE then
      local index = #CONNECTION_PREFACE + 1
      stream.preface = true
      logger:finer('preface received')
      return -1, index
    end
    stream.preface = false
    stream:onError('bad preface')
    return nil
  end
  if length < 9 then
    return nil
  end
  local frameLen = string.unpack('>I3', data)
  return 9 + frameLen
end

local function readPadding(flags, data, offset)
  if flags & PADDED_FLAG ~= 0 then
    local padLength = 0
    padLength, offset = string.unpack('>B', data, offset)
    logger:finer('padded %d', padLength)
    return offset, #data - padLength
  end
  return offset, #data
end

local function packSettings(settings)
  local parts = {}
  for setting, value in pairs(settings) do
    table.insert(parts, string.pack('>I2I4', setting, value))
  end
  return table.concat(parts)
end


local Stream = class.create(function(stream)

  function stream:initialize(http2, id)
    self.http2 = http2
    self.id = id
    self.message = HttpMessage:new()
  end

  function stream:sendHeaders(message, endStream)
    local data = self.http2.hpack:encodeHeaders(message)
    local flags = END_HEADERS_FLAG
    if endStream then
      flags = flags | END_STREAM_FLAG
    end
    return self.http2:sendFrame(FRAME.HEADERS, flags, self.id, data)
  end

  function stream:sendData(data)
    return self.http2:sendFrame(FRAME.DATA, END_STREAM_FLAG, self.id, data)
  end

end)

local Http2Handler = class.create(function(http2Handler)
  http2Handler.onHttp2EndHeaders = class.emptyFunction
  http2Handler.onHttp2EndStream = class.emptyFunction
  http2Handler.onHttp2Data = class.emptyFunction
  http2Handler.onHttp2Error = class.emptyFunction
end)

local DEFAULT = Http2Handler:new()

return class.create(function(http2)

  function http2:initialize(client, isServer, handler)
    self.client = client
    self.isServer = isServer
    self.handler = handler or DEFAULT
    self.hpack = Hpack:new()
    self.streams = {}
    self.streamNextId = isServer and 2 or 1
    self.settings = {
      --[SETTINGS.MAX_CONCURRENT_STREAMS] = 100, -- default unlimited
      --[SETTINGS.ENABLE_PUSH] = 0, -- disable server push, default 1 enabled
      --[SETTINGS.MAX_FRAME_SIZE] = 16384,
      --[SETTINGS.HEADER_TABLE_SIZE] = 4096,
      --[SETTINGS.MAX_HEADER_LIST_SIZE] = 0, -- default unlimited
      --[SETTINGS.INITIAL_WINDOW_SIZE] = 65535,
    }
  end

  function http2:readHeaderBlock(stream, flags, data, offset, endOffset)
    self.hpack:decodeHeaders(stream.message, data, offset, endOffset)
    if flags & END_HEADERS_FLAG ~= 0 then
      self.handler:onHttp2EndHeaders(stream)
    end
  end

  function http2:handleEndStream(flags, streamId, stream)
    stream = stream or self.streams[streamId]
    if flags & END_STREAM_FLAG ~= 0 then
      self.handler:onHttp2EndStream(stream)
      self.streams[streamId] = nil
    end
  end

  function http2:newStream(id)
    if id then
      if self.isServer and (id % 2 == 0) or (not self.isServer) and (id % 2 == 1) or self.streams[id] then
        error('invalid stream id')
      end
    else
      id = self.streamNextId
      self.streamNextId = self.streamNextId + 2
    end
    local stream = Stream:new(self, id)
    self.streams[id] = stream
    return stream
  end

  local function packFrame(frameType, flags, streamId, data)
    data = data or ''
    return string.pack('>I3BBI4', #data, frameType, flags, streamId)..data
  end

  function http2:sendFrame(frameType, flags, streamId, data)
    data = data or ''
    local frameLen = #data
    local frame = packFrame(frameType, flags, streamId, data)
    logger:fine('sending frame %s(%d), 0x%02x, id: %d, #%d', FRAME_BY_TYPE[frameType], frameType, flags, streamId, frameLen)
    --logger:finer('frame #%d: %s', #data, hex:encode(data))
    local p = self.client:write(frame)
    p:next(function()
      logger:fine('frame sent %s(%d), 0x%02x, id: %d', FRAME_BY_TYPE[frameType], frameType, flags, streamId)
    end, function(reason)
      logger:warn('frame sending failed %s(%d), 0x%02x, id: %d, #%d "%s"', FRAME_BY_TYPE[frameType], frameType, flags, streamId, frameLen, reason)
    end)
    return p
  end

  function http2:readStart()
    local client = self.client
    local cs = ChunkedStreamHandler:new(StreamHandler:new(function(err, data)
      if data then
        local frameType, flags, streamId = string.unpack('>BBI4', data, 4)
        streamId = streamId & 0x7fffffff
        local stream
        local frameLen = #data - 9
        logger:fine('received frame %s(%d), 0x%02x, id: %d, #%d', FRAME_BY_TYPE[frameType], frameType, flags, streamId, frameLen)
        local offset = 10
        local endOffset
        if frameType == FRAME.DATA then
          offset, endOffset = readPadding(flags, data, offset)
          stream = self.streams[streamId] -- TODO check stream
          self.handler:onHttp2Data(stream, string.sub(data, offset, endOffset))
          self:handleEndStream(flags, streamId, stream)
        elseif frameType == FRAME.HEADERS then
          if streamId == 0 then
            self:onError('invalid frame')
            return
          end
          offset, endOffset = readPadding(flags, data, offset)
          local streamDepExc, streamDep, weight
          if flags & PRIORITY_FLAG ~= 0 then
            streamDep, weight, offset = string.unpack('>I4B', data, offset)
            streamDepExc = streamDep >> 31 ~= 0
            streamDep = streamDep & 0x7fffffff
            logger:info('stream dep %s 0x%x %d', streamDepExc, streamDep, weight)
          end
          stream = self.streams[streamId]
          if stream then
            -- TODO check stream state
          else
            stream = self:newStream(streamId)
          end
          self:readHeaderBlock(stream, flags, data, offset, endOffset)
          self:handleEndStream(flags, streamId, stream)
        elseif frameType == FRAME.SETTINGS then
          if streamId ~= 0 or frameLen % 6 ~= 0 then
            self:onError('invalid frame')
            return
          end
          if flags & ACK_FLAG ~= 0 then
            logger:fine('settings ack received')
            return
          end
          logger:fine('settings received')
          local id, value
          while offset <= #data do
            id, value, offset = string.unpack('>I2I4', data, offset)
            logger:fine('setting %s(%d): %d', SETTINGS_BY_ID[id], id, value)
            if id == SETTINGS.MAX_HEADER_LIST_SIZE then
              self.hpack:resizeIndexes(value)
            end
          end
          self:sendFrame(FRAME.SETTINGS, ACK_FLAG, 0)
        elseif frameType == FRAME.WINDOW_UPDATE then
          local value = string.unpack('>I4', data, offset)
          value = value & 0x7fffffff
          logger:fine('window size increment: %d', value)
        elseif frameType == FRAME.RST_STREAM then
          if streamId == 0 or frameLen ~= 4 then
            self:onError('invalid frame')
            return
          end
          local errorCode = string.unpack('>I4', data, offset)
          stream = self.streams[streamId]
          self:handleStreamError(stream, errorCode)
        elseif frameType == FRAME.PUSH_PROMISE then
          offset, endOffset = readPadding(flags, data, offset)
          local promisedStreamId
          promisedStreamId, offset = string.unpack('>I4', data, offset)
          stream = self.streams[streamId]
          self:readHeaderBlock(stream, flags, data, offset, endOffset)
        elseif frameType == FRAME.PING then
          if flags & ACK_FLAG ~= 0 then
            logger:fine('ping ack received')
            return
          end
          self:sendFrame(FRAME.PING, ACK_FLAG, 0, string.sub(data, offset))
        elseif frameType == FRAME.GOAWAY then
          local lastStreamId, errorCode
          lastStreamId, errorCode, offset = string.unpack('>I4I4', data, offset)
          lastStreamId = lastStreamId & 0x7fffffff
          if errorCode ~= 0 then
            self:onError(string.format('go away, error %d: %s', errorCode, ERRORS_BY_ID[errorCode]))
            if offset >= #data then
              local debugData = string.sub(data, offset)
              self:onError(string.format('go away, debug "%s"', debugData))
            end
          end
        elseif frameType == FRAME.CONTINUATION then
          stream = self.streams[streamId]
          self:readHeaderBlock(stream, flags, data, offset)
        end
      elseif err then
        client:readStop()
        self:onError(err)
      end
    end), findFrame)
    logger:fine('start reading')
    client:readStart(cs)
    if not self.isServer then
      logger:fine('writing preface')
      client:write(CONNECTION_PREFACE):next(function()
        logger:fine('preface sent')
      end, function(reason)
        logger:warn('preface sending failed "%s"', reason)
      end)
    end
    return self:sendFrame(FRAME.SETTINGS, 0, 0, packSettings(self.settings))
  end

  function http2:goAway(errorCode)
    local lastStreamId = self.streamNextId -- TODO get correct value
    return self:sendFrame(FRAME.GOAWAY, 0, 0, string.pack('>I4I4', lastStreamId, errorCode or 0))
  end

  function http2:handleStreamError(stream, reason)
    logger:warn('stream %s error %s', stream.id, reason)
    self.handler:onHttp2Error(stream, reason)
  end

  function http2:onError(reason)
    logger:warn('h2 error %s', reason)
    self.handler:onHttp2Error(nil, reason)
  end

end, function(Http2)

  Http2.Stream = Stream

end)