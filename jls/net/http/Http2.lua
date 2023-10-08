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
  MAX_HEADER_LIST_SIZE = 6,
  ENABLE_CONNECT_PROTOCOL = 8, -- 1 to indicate to allow a client to use the Extended CONNECT, see RFC 8441
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
  OPEN = 1,
  RESERVED_LOCAL = 2,
  RESERVED_REMOTE = 3,
  HALF_CLOSED_LOCAL = 4,
  HALF_CLOSED_REMOTE = 5,
  CLOSED = 6,
}

local function findFrame(_, data, length)
  if length < 9 then
    return nil
  end
  local frameLen = string.unpack('>I3', data)
  return 9 + frameLen
end

local function findFrameWithPreface(sh, data, length)
  if sh.preface == nil then
    if length < #CONNECTION_PREFACE then
      return nil
    end
    if string.sub(data, 1, #CONNECTION_PREFACE) == CONNECTION_PREFACE then
      local index = #CONNECTION_PREFACE + 1
      sh.preface = true
      logger:finer('preface received')
      return -1, index
    end
    sh.preface = false
    sh:onError('bad preface')
    return nil
  end
  return findFrame(_, data, length)
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


local MAX_WINDOW_SIZE = (2 << 30) - 1

local Stream = class.create(function(stream)

  function stream:initialize(http2, id, message)
    self.http2 = http2
    self.id = id
    self.message = message or HttpMessage:new()
    self.message:setVersion('HTTP/2')
    self.state = STATE.IDLE
    self.windowSize = MAX_WINDOW_SIZE
    self.blockSize = self.http2.settings[SETTINGS.MAX_FRAME_SIZE] or 8192
    self.start_time = os.time()
  end

  function stream:onEndHeaders()
    if self.state == STATE.IDLE then
      self.state = STATE.OPEN
    end
  end

  function stream:sendHeaders(message, endStream)
    local data = self.http2.hpack:encodeHeaders(message)
    if self.state == STATE.IDLE then
      self.state = STATE.OPEN
    end
    return self.http2:sendFrame(FRAME.HEADERS, END_HEADERS_FLAG, self.id, data, endStream)
  end

  function stream:onData(data, endStream)
    local sh = self.message:getBodyStreamHandler()
    sh:onData(data)
    if endStream then
      sh:onData(nil)
    end
  end

  function stream:sendData(data, endStream)
    if data then
      local size = #data
      self.windowSize = self.windowSize - size
    end
    return self.http2:sendFrame(FRAME.DATA, 0, self.id, data, endStream)
  end

  function stream:sendBody(message)
    local endStream = false
    message:setBodyStreamHandler(StreamHandler:new(function(err, data, endData)
      if err then
        error(err)
      elseif data then
        if endData == true then
          endStream = true
        end
        self:sendData(data, endStream)
      elseif not endStream then
        self:sendData(nil, true)
      end
    end))
    message:writeBodyCallback(self.blockSize)
  end

  function stream:close()
    self.state = STATE.CLOSED
    self:onClose()
  end

  function stream:onClose()
  end

end)

local Http2Handler = class.create(function(http2Handler)
  http2Handler.onHttp2EndHeaders = class.emptyFunction
  http2Handler.onHttp2EndStream = class.emptyFunction
  http2Handler.onHttp2Event = class.emptyFunction
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
    self.windowSize = MAX_WINDOW_SIZE
    self.settings = {
      --[SETTINGS.MAX_CONCURRENT_STREAMS] = 100, -- default unlimited
      [SETTINGS.ENABLE_PUSH] = 0, -- disable server push, default 1 enabled
      [SETTINGS.MAX_FRAME_SIZE] = 65536,
      --[SETTINGS.HEADER_TABLE_SIZE] = 4096,
      --[SETTINGS.MAX_HEADER_LIST_SIZE] = 0, -- default unlimited
      [SETTINGS.INITIAL_WINDOW_SIZE] = MAX_WINDOW_SIZE,
      --[SETTINGS.ENABLE_CONNECT_PROTOCOL] = 1,
    }
  end

  function http2:handlePriority(streamId, data, offset, endOffset)
    local streamDepExc, streamDep, weight
    streamDep, weight, offset = string.unpack('>I4B', data, offset)
    streamDepExc = streamDep >> 31 ~= 0
    streamDep = streamDep & 0x7fffffff
    logger:finer('ignored stream dependency %d - %d, exclusive: %s, weight: %d', streamId, streamDep, streamDepExc, weight)
    return offset
  end

  function http2:handleHeaderBlock(stream, flags, data, offset, endOffset)
    self.hpack:decodeHeaders(stream.message, data, offset, endOffset)
    if flags & END_HEADERS_FLAG ~= 0 then
      stream:onEndHeaders()
      self.handler:onHttp2EndHeaders(stream)
    end
  end

  function http2:handleEndStream(flags, streamId, stream)
    if flags & END_STREAM_FLAG ~= 0 then
      logger:fine('end stream %d', streamId)
      stream = stream or self.streams[streamId]
      if stream then
        self.handler:onHttp2EndStream(stream)
        if stream.state == STATE.OPEN then
          stream.state = STATE.HALF_CLOSED_REMOTE
        elseif stream.state == STATE.HALF_CLOSED_LOCAL then
          self:closeStream(stream)
        end
      end
    end
  end

  function http2:newStream(idOrMessage)
    local id, message
    if type(idOrMessage) == 'number' then
      id = idOrMessage
      if self.isServer and (id % 2 == 0) or (not self.isServer) and (id % 2 == 1) or self.streams[id] then
        error('invalid stream id')
      end
    elseif HttpMessage:isInstance(idOrMessage) then
      message = idOrMessage
    else
      error('invalid argument')
    end
    if not id then
      id = self.streamNextId
      self.streamNextId = self.streamNextId + 2
    end
    local stream = Stream:new(self, id, message)
    self.streams[id] = stream
    logger:fine('new stream %d', id)
    return stream
  end

  function http2:closeStream(stream)
    self.streams[stream.id] = nil
    stream:close()
    if next(self.streams) == nil then
      self.handler:onHttp2Event('empty', self)
    end
  end

  function http2:sendFrame(frameType, flags, streamId, data, endStream)
    data = data or ''
    local frameLen = #data
    if frameType <= 1 then -- HEADERS or DATA
      if endStream then
        flags = flags | END_STREAM_FLAG
        local stream = self.streams[streamId]
        if stream.state == STATE.OPEN then
          stream.state = STATE.HALF_CLOSED_LOCAL
        elseif stream.state == STATE.HALF_CLOSED_REMOTE then
          self:closeStream(stream)
        end
      end
      if frameType == FRAME.DATA then
        self.windowSize = self.windowSize - frameLen
      end
    end
    local frame = string.pack('>I3BBI4', frameLen, frameType, flags, streamId)..data
    if logger:isLoggable(logger.FINE) then
      logger:fine('sending frame %s(%d), 0x%02x, id: %d, #%d', FRAME_BY_TYPE[frameType], frameType, flags, streamId, frameLen)
      --logger:finer('frame #%d: %s', #data, hex:encode(data))
    end
    local p = self.client:write(frame)
    if logger:isLoggable(logger.FINE) then
      p:next(function()
        logger:fine('frame sent %s(%d), 0x%02x, id: %d', FRAME_BY_TYPE[frameType], frameType, flags, streamId)
      end, function(reason)
        logger:warn('frame sending failed %s(%d), 0x%02x, id: %d, #%d "%s"', FRAME_BY_TYPE[frameType], frameType, flags, streamId, frameLen, reason)
      end)
    end
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
        if logger:isLoggable(logger.FINER) then
          logger:finer('received frame %s(%d), 0x%02x, id: %d, #%d', FRAME_BY_TYPE[frameType], frameType, flags, streamId, frameLen)
        end
        local offset = 10
        local endOffset
        if frameType == FRAME.DATA then
          offset, endOffset = readPadding(flags, data, offset)
          stream = self.streams[streamId]
          if not stream then
            self:onError(string.format('unknown stream id %d', streamId))
            return
          end
          stream:onData(string.sub(data, offset, endOffset), flags & END_STREAM_FLAG ~= 0)
          self:handleEndStream(flags, streamId, stream)
        elseif frameType == FRAME.HEADERS then
          if streamId == 0 then
            self:onError('invalid frame')
            return
          end
          offset, endOffset = readPadding(flags, data, offset)
          if flags & PRIORITY_FLAG ~= 0 then
            offset = self:handlePriority(streamId, data, offset, endOffset)
          end
          stream = self.streams[streamId]
          if not stream then
            stream = self:newStream(streamId)
          end
          self:handleHeaderBlock(stream, flags, data, offset, endOffset)
          self:handleEndStream(flags, streamId, stream)
        elseif frameType == FRAME.PRIORITY then
          offset = self:handlePriority(streamId, data, offset, endOffset)
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
            local currentValue = self.settings[id]
            if logger:isLoggable(logger.FINE) then
              logger:fine('setting %s(%d): %d was %s', SETTINGS_BY_ID[id], id, value, currentValue)
            end
            if currentValue then
              self.settings[id] = math.min(currentValue, value)
            else
              self.settings[id] = value
            end
            if id == SETTINGS.HEADER_TABLE_SIZE then
              self.hpack:resizeIndexes(value)
            end
          end
          self:sendFrame(FRAME.SETTINGS, ACK_FLAG, 0)
        elseif frameType == FRAME.WINDOW_UPDATE then
          local value = string.unpack('>I4', data, offset)
          value = value & 0x7fffffff
          logger:finer('window size increment: %d for stream %d', value, streamId)
          if streamId == 0 then
            self.windowSize = self.windowSize + value
          else
            stream = self.streams[streamId]
            if not stream then
              self:onError(string.format('unknown stream id %d', streamId))
              return
            end
            stream.windowSize = stream.windowSize + value
          end
        elseif frameType == FRAME.RST_STREAM then
          if streamId == 0 or frameLen ~= 4 then
            self:onError('invalid frame')
            return
          end
          local errorCode = string.unpack('>I4', data, offset)
          stream = self.streams[streamId]
          self:handleStreamError(stream, errorCode)
        elseif frameType == FRAME.PUSH_PROMISE then
          logger:warn('push promise received')
        elseif frameType == FRAME.PING then
          if flags & ACK_FLAG ~= 0 then
            logger:fine('ping ack received')
            return
          end
          self.handler:onHttp2Event('ping', self)
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
          if not stream then
            self:onError(string.format('unknown stream id %d', streamId))
            return
          end
          self:handleHeaderBlock(stream, flags, data, offset)
        end
      elseif err then
        client:readStop()
        self:onError(err)
      end
    end), self.isServer and findFrameWithPreface or findFrame)
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
    logger:warn('stream %s error %s', stream and stream.id, reason)
    self.handler:onHttp2Event('stream-error', self, stream, reason)
  end

  function http2:onError(reason)
    logger:warn('h2 error %s', reason)
    self.handler:onHttp2Event('error', self, nil, reason)
  end

  function http2:close()
    logger:fine('http2:close()')
    return self:goAway()
  end

end, function(Http2)

  Http2.Stream = Stream

end)