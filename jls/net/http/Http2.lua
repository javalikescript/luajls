local class = require('jls.lang.class')
local logger = require('jls.lang.loggerFactory')(...)
local Promise = require('jls.lang.Promise')
local StreamHandler = require('jls.io.StreamHandler')
local ChunkedStreamHandler = require('jls.io.streams.ChunkedStreamHandler')
local Hpack = require('jls.net.http.Hpack')
local HttpMessage = require('jls.net.http.HttpMessage')
local Map = require('jls.util.Map')
local strings = require('jls.util.strings')

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


local Stream = class.create(function(stream)

  function stream:initialize(http2, id, message)
    self.http2 = http2
    self.id = id
    self.message = message or HttpMessage:new()
    self.message:setVersion('HTTP/2')
    self.state = STATE.IDLE
    self.blockSize = http2:getRemoteSetting(SETTINGS.MAX_FRAME_SIZE)
    self.sendWindowSize = http2:getRemoteSetting(SETTINGS.INITIAL_WINDOW_SIZE)
    self.recvWindowSize = self.http2.initialWindowSize
    self.recvMinSize = self.http2.initialWindowSize * 3 // 4
    self.start_time = os.time()
  end

  function stream:onEndHeaders()
    logger:finer('stream:onEndHeaders()')
    if self.state == STATE.IDLE then
      self.state = STATE.OPEN
    end
  end

  function stream:onEndStream()
    logger:finer('stream:onEndStream()')
    if self.state == STATE.OPEN then
      self.state = STATE.HALF_CLOSED_REMOTE
    elseif self.state == STATE.HALF_CLOSED_LOCAL then
      self.http2:closedStream(self)
    end
  end

  function stream:onWindowUpdate(increment)
    self.sendWindowSize = self.sendWindowSize + increment
    if logger:isLoggable(logger.FINE) then
      logger:fine('window size increment: %d for stream %d, new size is %d', increment, self.id, self.sendWindowSize)
    end
    local sendCallback = self.sendCallback
    if sendCallback then
      self.sendCallback = nil
      logger:fine('calling back stream %d buffer', self.id)
      sendCallback()
    end
  end

  function stream:onError(reason)
    logger:warn('h2 stream %s in error due to %s', self.id, reason)
    local sendCallback = self.sendCallback
    if sendCallback then
      self.sendCallback = nil
      sendCallback(reason)
    end
  end

  function stream:onClose()
  end

  function stream:doEndStream()
    logger:finer('stream:doEndStream()')
    if self.state == STATE.OPEN then
      self.state = STATE.HALF_CLOSED_LOCAL
    elseif self.state == STATE.HALF_CLOSED_REMOTE then
      self.http2:closedStream(self)
    end
  end

  function stream:sendHeaders(message, endHeaders, endStream)
    logger:finer('stream:sendHeaders(?, %s, %s)', endHeaders, endStream)
    if endHeaders and self.state == STATE.IDLE then
      self.state = STATE.OPEN
    end
    local p = self.http2:sendHeaders(self.id, message, endHeaders, endStream)
    if endStream then
      self:doEndStream()
    end
    return p
  end

  function stream:onHeaders(endHeaders, endStream)
    if endHeaders then
      self:onEndHeaders()
    end
    if endStream then
      self:onEndStream()
    end
  end

  function stream:onData(data)
    local sh = self.message:getBodyStreamHandler()
    sh:onData(data)
  end

  function stream:onRawData(data, endStream)
    logger:finer('stream:onRawData(?, %s)', endStream)
    local size = #data
    self.recvWindowSize = self.recvWindowSize - size
    -- TODO send window update
    if self.recvWindowSize < self.recvMinSize and not endStream then
      self:sendWindowUpdate(self.http2.initialWindowSize - self.recvWindowSize)
    end
    if size > 0 then
      self:onData(data)
    end
    if endStream then
      self:onData(nil)
      self:onEndStream()
    end
  end

  function stream:waitWindowUpdate(data, endStream)
    local sendCallback = self.sendCallback
    if sendCallback then
      self.sendCallback = nil
      sendCallback('window size too small again')
      return Promise.reject('window size too small again')
    end
    return Promise:new(function(resolve, reject)
      logger:fine('registering buffer callback for stream %d', self.id)
      self.sendCallback = function(err)
        if err then
          reject(err)
        elseif #data > self.sendWindowSize then
          reject('window size still too small')
        else
          resolve(self:sendData(data, endStream))
        end
      end
    end)
  end

  function stream:sendData(data, endStream)
    local size = data and #data or 0
    logger:finer('stream:sendData(#%d, %s)', size, endStream)
    if size <= self.blockSize then
      if size > 0 and size > self.sendWindowSize then
        logger:fine('stream window size too small (%d, frame is %d)', self.sendWindowSize, size)
        return self:waitWindowUpdate(data, endStream)
      end
      self.sendWindowSize = self.sendWindowSize - size
      local p = self.http2:sendData(self.id, data, endStream)
      if endStream then
        self:doEndStream()
      end
      return p
    end
    local p = Promise.resolve()
    for value, ends in strings.parts(data, self.blockSize) do
      local v, e = value, ends and endStream
      p = p:next(function()
        return self:sendData(v, e)
      end)
    end
    return p
  end

  function stream:sendWindowUpdate(increment)
    logger:fine('send stream window update %d', increment)
    return self.http2:sendFrame(FRAME.WINDOW_UPDATE, 0, self.id, string.pack('>I4', increment)):next(function()
      self.recvWindowSize = self.recvWindowSize + increment
    end)
  end

  function stream:sendBody(message)
    logger:finer('stream:sendBody()')
    local endStream = false
    message:setBodyStreamHandler(StreamHandler:new(function(err, data, endData)
      if err then
        error(err)
      elseif data then
        if endStream then
          logger:warn('stream ended')
          return
        end
        if endData == true then
          endStream = true
        end
        return self:sendData(data, endStream)
      elseif not endStream then
        return self:sendData(nil, true)
      end
    end))
    message:writeBodyCallback(self.blockSize)
  end

  function stream:close()
    logger:finer('stream:close()')
    self.state = STATE.CLOSED
    self:onClose()
  end

end)

return class.create(function(http2)

  function http2:initialize(client, isServer)
    self.client = client
    self.isServer = isServer
    self.hpack = Hpack:new()
    self.streams = {}
    self.streamNextId = isServer and 2 or 3
    local initialWindowSize = 65535
    -- some settings have a default value
    -- settings are set by the remote peer
    self.settings = {
      [SETTINGS.ENABLE_PUSH] = 1,
      [SETTINGS.HEADER_TABLE_SIZE] = 4096,
      --[SETTINGS.MAX_CONCURRENT_STREAMS] = unlimited,
      [SETTINGS.MAX_FRAME_SIZE] = 16384,
      --[SETTINGS.MAX_HEADER_LIST_SIZE] = unlimited,
      [SETTINGS.INITIAL_WINDOW_SIZE] = initialWindowSize,
    }
    self.sendWindowSize = initialWindowSize -- send window size
    self.recvTargetSize = 15728640
    self.recvMinSize = self.recvTargetSize * 3 // 4
    self.recvWindowSize = initialWindowSize -- receipt window size
    self.initialWindowSize = initialWindowSize
    self.pingMap = {}
    self.pingIndex = 0
    self.settingAcks = {}
    self.initialSettingsPromise, self.initialSettingsCb = Promise.createWithCallback()
  end

  function http2:getRemoteSetting(id)
    return self.settings[id]
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
    stream:onHeaders(flags & END_HEADERS_FLAG ~= 0, flags & END_STREAM_FLAG ~= 0)
  end

  function http2:nextStreamId()
    local id = self.streamNextId
    self.streamNextId = self.streamNextId + 2
    return id
  end

  function http2:newStream(id)
    return Stream:new(self, id)
  end

  function http2:registerStream(stream)
    -- The first use of a new stream identifier implicitly closes all streams in the "idle" state
    -- that might have been initiated by that peer with a lower-valued stream identifier.
    self.streams[stream.id] = stream
    if logger:isLoggable(logger.FINE) then
      logger:fine('register stream %d, %s', stream.id, self:toPrettyString())
    end
    return stream
  end

  function http2:closedStream(stream)
    self.streams[stream.id] = nil
    if logger:isLoggable(logger.FINE) then
      logger:fine('end stream %d, %s', stream.id, self:toPrettyString())
    end
    stream:close()
  end

  function http2:toPrettyString()
    return self.isServer and 'server' or 'client'
  end

  function http2:sendFrame(frameType, flags, streamId, data)
    data = data or ''
    local frameLen = #data
    local frame = string.pack('>I3BBI4', frameLen, frameType, flags, streamId)..data
    if logger:isLoggable(logger.FINE) then
      logger:fine('sending frame %s(%d), 0x%02x, id: %d, #%d, %s', FRAME_BY_TYPE[frameType], frameType, flags, streamId, frameLen, self:toPrettyString())
      --logger:finer('frame #%d: %s', #data, hex:encode(data))
    end
    local p = self.client:write(frame)
    if logger:isLoggable(logger.FINER) then
      p:next(function()
        logger:finer('frame sent %s(%d), 0x%02x, id: %d', FRAME_BY_TYPE[frameType], frameType, flags, streamId)
      end, function(reason)
        logger:warn('frame sending failed %s(%d), 0x%02x, id: %d, #%d "%s"', FRAME_BY_TYPE[frameType], frameType, flags, streamId, frameLen, reason)
      end)
    end
    return p:catch(function(reason)
      if frameType == FRAME.GOAWAY then
        logger:fine('write error ignored "%s"', reason)
      else
        self:handleError('write error "%s" %s(%d), 0x%02x, id: %d', reason, FRAME_BY_TYPE[frameType], frameType, flags, streamId)
        Promise.reject(reason)
      end
    end)
  end

  function http2:sendHeaders(streamId, message, endHeaders, endStream)
    logger:finer('http2:sendHeaders(%d, ?, %s, %s)', streamId, endHeaders, endStream)
    local flags = endHeaders and END_HEADERS_FLAG or 0
    if endStream then
      flags = flags | END_STREAM_FLAG
    end
    local data = self.hpack:encodeHeaders(message)
    return self:sendFrame(FRAME.HEADERS, flags, streamId, data)
  end

  function http2:sendData(streamId, data, endStream)
    logger:finer('http2:sendData(%d, ?, %s)', streamId, endStream)
    data = data or ''
    local frameLen = #data
    if frameLen > self.sendWindowSize then
      logger:warn('h2 window size too small (%d, frame is %d)', self.sendWindowSize, frameLen)
      return Promise.reject('window size too small')
    end
    self.sendWindowSize = self.sendWindowSize - frameLen
    local flags = endStream and END_STREAM_FLAG or 0
    return self:sendFrame(FRAME.DATA, flags, streamId, data)
  end

  function http2:sendSettings(settings, preface)
    logger:fine('http2:sendSettings(), preface: %s', preface)
    settings = settings or {}
    local initialWindowSize = settings[SETTINGS.INITIAL_WINDOW_SIZE]
    if initialWindowSize then
      self.initialWindowSize = initialWindowSize
    end
    local data = packSettings(settings)
    data = string.pack('>I3BBI4', #data, FRAME.SETTINGS, 0, 0)..data
    if preface then
      data = CONNECTION_PREFACE..data
    end
    return self.client:write(data):next(function()
      table.insert(self.settingAcks, {settings = settings, time = os.time()})
    end, function(reason)
      self:handleError(string.format('write settings error %s', reason))
      Promise.reject(reason)
    end)
  end

  function http2:sendWindowUpdate(increment)
    logger:fine('http2:sendWindowUpdate(%d)', increment)
    return self:sendFrame(FRAME.WINDOW_UPDATE, 0, 0, string.pack('>I4', increment)):next(function()
      self.recvWindowSize = self.recvWindowSize + increment
    end)
  end

  function http2:sendPing()
    -- TODO timeout
    -- TODO clean pingMap
    local max = 2^16
    self.pingIndex = (self.pingIndex + 1) % max
    local pingData = string.format('%04x%04x', math.random(0, max - 1), self.pingIndex)
    logger:fine('http2:sendPing() "%s"', pingData)
    return self:sendFrame(FRAME.PING, 0, 0, pingData):next(function()
      local p, cb = Promise.createWithCallback()
      self.pingMap[pingData] = {cb = cb, time = os.time()}
      return p
    end)
  end

  function http2:readStart(settings)
    local client = self.client
    local cs = ChunkedStreamHandler:new(StreamHandler:new(function(err, data)
      if err then
        if err == 'SSL connection closed' then
          logger:info('h2 read error "%s", closing', err)
          self:doClose()
        else
          self:handleError('read error "%s"', err)
        end
      elseif data then
        local frameType, flags, streamId = string.unpack('>BBI4', data, 4)
        streamId = streamId & 0x7fffffff
        local stream
        local frameLen = #data - 9
        if logger:isLoggable(logger.FINE) then
          logger:fine('received frame %s(%d), 0x%02x, id: %d, #%d, %s', FRAME_BY_TYPE[frameType], frameType, flags, streamId, frameLen, self:toPrettyString())
        end
        local offset, endOffset
        offset = 10
        if frameType == FRAME.DATA then
          stream = self:checkStreamFrame(streamId)
          if stream then
            if stream.state ~= STATE.OPEN and stream.state ~= STATE.HALF_CLOSED_LOCAL then
              self:goAway(ERRORS.STREAM_CLOSED, 'bad stream state (%s)', stream.state)
              return
            end
            offset, endOffset = readPadding(flags, data, offset)
            if offset < endOffset then
              self.recvWindowSize = self.recvWindowSize - (endOffset - offset + 1)
              if self.recvWindowSize < self.recvMinSize then
                self:sendWindowUpdate(self.recvTargetSize - self.recvWindowSize)
              end
            end
            stream:onRawData(string.sub(data, offset, endOffset), flags & END_STREAM_FLAG ~= 0)
          end
        elseif frameType == FRAME.HEADERS then
          if self:checkFrame(streamId == 0) then
            return
          end
          offset, endOffset = readPadding(flags, data, offset)
          if flags & PRIORITY_FLAG ~= 0 then
            offset = self:handlePriority(streamId, data, offset, endOffset)
          end
          if self.isServer == (streamId % 2 == 0) then
            stream = self:checkStreamFrame(streamId)
          else
            stream = self.streams[streamId]
            if not stream then
              stream = self:newStream(streamId)
              self:registerStream(stream)
            end
          end
          if stream then
            self:handleHeaderBlock(stream, flags, data, offset, endOffset)
          end
        elseif frameType == FRAME.PRIORITY then
          if self:checkFrame(streamId == 0, frameLen ~= 5) then
            return
          end
          offset = self:handlePriority(streamId, data, offset, endOffset)
        elseif frameType == FRAME.SETTINGS then
          if self:checkFrame(streamId ~= 0, frameLen % 6 ~= 0) then
            return
          end
          if flags & ACK_FLAG ~= 0 then
            logger:fine('settings ack received')
            local ack = table.remove(self.settingAcks, 1)
            if ack then
              self:onSettingsAck(ack.settings)
            end
            return
          end
          logger:fine('settings received')
          local settings = {}
          local id, value
          while offset <= #data do
            id, value, offset = string.unpack('>I2I4', data, offset)
            if logger:isLoggable(logger.FINE) then
              logger:fine('setting %s(%d): %d was %s', SETTINGS_BY_ID[id], id, value, self.settings[id])
            end
            settings[id] = value
            self.settings[id] = value
            if id == SETTINGS.HEADER_TABLE_SIZE then
              self.hpack:resizeIndexes(value)
            end
          end
          self:sendFrame(FRAME.SETTINGS, ACK_FLAG, 0)
          if self.initialSettingsCb then
            self.initialSettingsCb()
            self.initialSettingsCb = nil
            self.initialSettingsPromise = nil
          end
          self:onSettings(settings)
        elseif frameType == FRAME.WINDOW_UPDATE then
          if self:checkFrame(nil, frameLen ~= 4) then
            return
          end
          local value = string.unpack('>I4', data, offset)
          value = value & 0x7fffffff
          if streamId == 0 then
            self.sendWindowSize = self.sendWindowSize + value
            logger:fine('window size increment: %d, new size is %d', value, self.sendWindowSize)
          else
            stream = self:checkStreamFrame(streamId)
            if stream then
              stream:onWindowUpdate(value)
            end
          end
        elseif frameType == FRAME.RST_STREAM then
          stream = self:checkStreamFrame(streamId, frameLen ~= 4)
          if stream then
            local errorCode = string.unpack('>I4', data, offset)
            stream:handleError(errorCode)
          end
        elseif frameType == FRAME.PUSH_PROMISE then
          if self:checkFrame(streamId == 0) then
            return
          end
          logger:warn('push promise rejected')
          self:sendFrame(FRAME.RST_STREAM, 0, streamId)
        elseif frameType == FRAME.PING then
          if self:checkFrame(streamId ~= 0, frameLen ~= 8) then
            return
          end
          local pingData = string.sub(data, offset)
          if flags & ACK_FLAG ~= 0 then
            logger:fine('ping ack received "%s"', pingData)
            local ack = self.pingMap[pingData]
            if ack then
              self.pingMap[pingData] = nil
              ack.cb()
            end
            return
          end
          self:sendFrame(FRAME.PING, ACK_FLAG, 0, pingData)
          self:onPing(pingData)
        elseif frameType == FRAME.GOAWAY then
          if self:checkFrame(streamId ~= 0, frameLen < 8) then
            return
          end
          local lastStreamId, errorCode
          lastStreamId, errorCode, offset = string.unpack('>I4I4', data, offset)
          lastStreamId = lastStreamId & 0x7fffffff
          if errorCode ~= 0 then
            if offset < #data then
              local debugData = string.sub(data, offset)
              self:handleError('go away, error %d: %s, debug "%s"', errorCode, ERRORS_BY_ID[errorCode], debugData)
            else
              self:handleError('go away, error %d: %s', errorCode, ERRORS_BY_ID[errorCode])
            end
          end
        elseif frameType == FRAME.CONTINUATION then
          stream = self:checkStreamFrame(streamId)
          if stream then
            self:handleHeaderBlock(stream, flags, data, offset)
          end
        else
          -- Implementations MUST ignore and discard any frame that has a type that is unknown.
          logger:fine('ignore unknown frame type %d', frameType)
        end
      else
        logger:info('end of h2 reading')
        self:doClose()
      end
    end), self.isServer and findFrameWithPreface or findFrame)
    if logger:isLoggable(logger.FINE) then
      logger:fine('start reading, %s', self:toPrettyString())
    end
    client:readStart(cs)
    return self:sendSettings(settings, not self.isServer)
  end

  function http2:checkStreamFrame(id, frameLenCheck)
    if frameLenCheck ~= nil and frameLenCheck then
      self:goAway(ERRORS.FRAME_SIZE_ERROR, 'invalid frame size')
      return
    end
    if id == 0 then
      self:goAway(ERRORS.PROTOCOL_ERROR, 'missing stream id')
      return
    end
    local stream = self.streams[id]
    if stream then
      return stream
    end
    self:onError(string.format('unknown stream id %d', id))
  end

  function http2:checkFrame(streamIdCheck, frameLenCheck)
    if frameLenCheck ~= nil and frameLenCheck then
      self:goAway(ERRORS.FRAME_SIZE_ERROR, 'invalid frame size')
      return true
    end
    if streamIdCheck ~= nil and streamIdCheck then
      self:goAway(ERRORS.PROTOCOL_ERROR, 'invalid stream id')
      return true
    end
  end

  function http2:goAway(errorCode, debugData, ...)
    if logger:isLoggable(logger.FINE) then
      logger:fine('http2:goAway(%s, %s)', errorCode, debugData and string.format(debugData, ...))
    end
    local lastStreamId = self.streamNextId -- TODO get correct value
    local data = string.pack('>I4I4', lastStreamId, errorCode or 0)
    if errorCode and errorCode ~= 0 and debugData then
      data = data..string.format(debugData, ...)
    end
    return self:sendFrame(FRAME.GOAWAY, 0, 0, data):finally(function()
      self:doClose()
    end)
  end

  function http2:doClose()
    self.client:readStop()
    self.client:close()
  end

  function http2:handleError(reason, ...)
    self:doClose()
    if type(reason) == 'string' then
      self:onError(string.format(reason, ...))
    else
      self:onError(reason)
    end
  end

  function http2:initialSettings()
    return self.initialSettingsPromise
  end

  function http2:onSettings(settings)
  end

  function http2:onSettingsAck(settings)
  end

  function http2:onPing(pingData)
  end

  function http2:onError(reason)
    logger:warn('h2 error %s', reason)
  end

  function http2:close()
    logger:fine('http2:close()')
    return self:goAway()
  end

end, function(Http2)

  Http2.Stream = Stream
  Http2.SETTINGS = SETTINGS
  Http2.STATE = STATE

end)