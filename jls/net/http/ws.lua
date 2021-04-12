--- This module provide classes to work with WebSocket.
-- @module jls.net.http.ws
-- @pragma nostrip

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local HttpMessage = require('jls.net.http.HttpMessage')
local HttpClient = require('jls.net.http.HttpClient')
local base64 = require('jls.util.base64')
local md = require('jls.util.MessageDigest'):new('sha1')

local hex = require('jls.util.hex')

local CONST = {
  HEADER_SEC_WEBSOCKET_KEY = 'Sec-WebSocket-Key',
  HEADER_SEC_WEBSOCKET_ACCEPT = 'Sec-WebSocket-Accept',
  HEADER_SEC_WEBSOCKET_VERSION = 'Sec-WebSocket-Version',
  HEADER_SEC_WEBSOCKET_PROTOCOL = 'Sec-WebSocket-Protocol',

  CONNECTION_UPGRADE = 'Upgrade',
  UPGRADE_WEBSOCKET = 'websocket',

  WEBSOCKET_VERSION = 13,

  OP_CODE_CONTINUATION = 0,
  OP_CODE_TEXT_FRAME = 1,
  OP_CODE_BINARY_FRAME = 2,
  OP_CODE_CLOSE = 8,
  OP_CODE_PING = 9,
  OP_CODE_PONG = 10
}

--[[
    NOTE: As an example, if the value of the |Sec-WebSocket-Key| header
   field in the client's handshake were "dGhlIHNhbXBsZSBub25jZQ==", the
   server would append the string "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
   to form the string "dGhlIHNhbXBsZSBub25jZQ==258EAFA5-E914-47DA-95CA-
   C5AB0DC85B11".  The server would then take the SHA-1 hash of this
   string, giving the value 0xb3 0x7a 0x4f 0x2c 0xc0 0x62 0x4f 0x16 0x90
   0xf6 0x46 0x06 0xcf 0x38 0x59 0x45 0xb2 0xbe 0xc4 0xea.  This value
   is then base64-encoded, to give the value
   "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", which would be returned in the
   |Sec-WebSocket-Accept| header field.
]]
local function hashWebSocketKey(key)
  return base64.encode(md:digest(key..'258EAFA5-E914-47DA-95CA-C5AB0DC85B11'))
end

--math.randomseed(os.time())

local function randomChars(len)
  local buffer = ''
  for i = 1, len do
    buffer = buffer..string.char(math.random(0, 255))
  end
  return buffer
end


--- The WebSocketBase class represents the base class for WebSocket.
-- @type WebSocketBase
local WebSocketBase = class.create(function(webSocketBase)

  --- Creates a new WebSocket.
  -- @function WebSocketBase:new
  function webSocketBase:initialize(tcp)
    self.tcp = tcp
    self.mask = true
  end

  function webSocketBase:onReadError(err)
    if logger:isLoggable(logger.FINE) then
      logger:fine('webSocketBase:onReadError("'..tostring(err)..'")')
    end
  end

  local function read2BytesHeader(buffer)
    local b1, b2 = string.byte(buffer, 1, 2)
    local fin = (b1 >> 7) == 0x01
    local rsv = (b1 >> 4) & 0x07
    local opcode = b1 & 0x0f
    local mask = (b2 >> 7) == 0x01
    local len = b2 & 0x7f
    if logger:isLoggable(logger.FINE) then
      logger:fine('WebSocket readHeader(), fin: '..tostring(fin)..', rsv: '..tostring(rsv)..', opcode: '..tostring(opcode)..', mask: '..tostring(mask)..', len: '..tostring(len))
    end
    -- Payload length:  7 bits, 7+16 bits, or 7+64 bits
    -- If 126, the following 2 bytes interpreted as a 16-bit unsigned integer are the payload length.
    -- If 127, the following 8 bytes interpreted as a 64-bit unsigned integer (the most significant bit MUST be 0) are the payload length.
    local sizeLength
    if len < 126 then
      sizeLength = 0
    else
      if len == 126 then
        sizeLength = 2
      else
        sizeLength = 8
      end
    end
    -- Masking-key:  0 or 4 bytes
    local maskLength
    if mask then
      maskLength = 4
    else
      maskLength = 0
    end
    return fin, opcode, len, sizeLength, maskLength, rsv
  end

  --- Closes this WebSocket.
  -- @tparam function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the WebSocket is closed.
  function webSocketBase:close(callback)
    return self.tcp:close(callback)
  end

  local function applyMask(maskTable, payload)
    local buffer = ''
    local maskLength = #maskTable
    for i = 1, #payload do
        local j = ((i - 1) % maskLength) + 1
        local x = string.byte(payload, i) ~ string.byte(maskTable, j)
        buffer = buffer..string.char(x)
    end
    return buffer
  end

  function webSocketBase:onTextMessage(message)
    if logger:isLoggable(logger.FINE) then
      logger:fine('webSocketBase:onTextMessage("'..tostring(message)..'")')
    end
  end

  function webSocketBase:onBinaryMessage(message)
    if logger:isLoggable(logger.FINE) then
      logger:fine('webSocketBase:onBinaryMessage()')
    end
  end

  function webSocketBase:onReadFrame(fin, opcode, payload)
    if logger:isLoggable(logger.FINE) then
      logger:fine('webSocketBase:onReadFrame('..tostring(fin)..', '..tostring(opcode)..', '..tostring(#payload)..')')
    end
    if fin then
      if opcode == CONST.OP_CODE_TEXT_FRAME then
        self:onTextMessage(payload)
      elseif opcode == CONST.OP_CODE_BINARY_FRAME then
        self:onBinaryMessage(payload)
      end
    end
  end

  --- Stops receiving messages on this WebSocket.
  function webSocketBase:readStop()
    return self.tcp:readStop()
  end

  --- Starts receiving messages on this WebSocket.
  function webSocketBase:readStart()
    -- stream implementation that buffers and splits packets
    local buffer = ''
    return self.tcp:readStart(function(err, data)
      if err then
        self:onReadError(err)
      elseif data then
        buffer = buffer..data
        while true do
          local bufferLength = #buffer
          if bufferLength < 2 then
            break
          end
          local fin, opcode, len, sizeLength, maskLength, rsv = read2BytesHeader(buffer)
          local headerLength = 2 + sizeLength + maskLength
          if bufferLength < headerLength then
            break
          end
          local idx = 3
          if sizeLength > 0 then
              len = 0
              for i = idx, idx + sizeLength - 1 do
                  len = (len * 256) + string.byte(data, i)
              end
              idx = idx + sizeLength
          end
          local maskChars
          if maskLength > 0 then
              maskChars = string.sub(data, idx, idx + maskLength - 1)
              idx = idx + maskLength
          end
          local frameLength = headerLength + len
          if bufferLength < frameLength then
            break
          end
          local payload = string.sub(data, idx, idx + len - 1)
          if maskChars then
              payload = applyMask(maskChars, payload)
          end
          local remainingBuffer
          if bufferLength == frameLength then
            remainingBuffer = ''
          else
            remainingBuffer = string.sub(buffer, frameLength + 1)
            buffer = string.sub(buffer, 1, frameLength)
          end
          self:onReadFrame(fin, opcode, payload)
          buffer = remainingBuffer
        end
      end
    end)
  end

  function webSocketBase:sendFrame(fin, opcode, mask, payload, callback)
    if not payload then
      payload = ''
    end
    if logger:isLoggable(logger.FINE) then
      logger:fine('webSocketBase:sendFrame('..tostring(fin)..', '..tostring(opcode)..', '..tostring(mask)..')')
    end
    local b1 = 0
    if fin then
      b1 = 0x80
    end
    b1 = b1 + (opcode & 0x0f)
    local payloadLength = #payload
    local len, sizeLength
    if payloadLength < 126 then
      len = payloadLength
      sizeLength = 0
    elseif payloadLength < 65536 then
      len = 126
      sizeLength = 2
    else
      len = 127
      sizeLength = 8
    end
    local b2 = 0
    if mask then
      b2 = 0x80
    end
    b2 = b2 + (len & 0x7f)
    local header = string.char(b1, b2)
    local sizeChars = ''
    for i = 1, sizeLength do
      sizeChars = string.char(payloadLength & 0xff)..sizeChars
      payloadLength = payloadLength // 256
    end
    header = header..sizeChars
    if mask then
      local maskChars = randomChars(4)
      header = header..maskChars
      payload = applyMask(maskChars, payload)
    end
    if logger:isLoggable(logger.FINE) then
      logger:fine('webSocketBase:sendFrame() '..hex.encode(header..payload))
    end
    return self.tcp:write(header..payload, callback)
  end

  --- Sends a message on this WebSocket.
  -- @tparam string message the message to send.
  -- @tparam function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the data has been written.
  function webSocketBase:sendTextMessage(message, callback)
    if logger:isLoggable(logger.FINE) then
      logger:fine('webSocketBase:sendTextMessage("'..tostring(message)..'")')
    end
    return self:sendFrame(true, CONST.OP_CODE_TEXT_FRAME, self.mask, message, callback)
  end

end)


--[[--
The WebSocket class enables to send and receive messages.
see https://tools.ietf.org/html/rfc6455
@usage
local event = require('jls.lang.event')
local ws = require('jls.net.http.ws')
local webSocket = ws.WebSocket:new('ws://localhost/ws/')
webSocket:open():next(function()
  function webSocket:onTextMessage(payload)
    webSocket:close()
  end
  webSocket:readStart()
  webSocket:sendTextMessage('Hello')
end)
event:loop()
@type WebSocket
]]
local WebSocket = class.create(WebSocketBase, function(webSocket, super)

  --- Creates a new WebSocket.
  -- @function WebSocket:new
  -- @tparam string url A table describing the client options.
  -- @return a new WebSocket
  function webSocket:initialize(url, protocols)
    self.url = url
    self.protocols = protocols
    super.initialize(self)
  end

  function webSocket:open()
    -- The value of this header field MUST be a nonce consisting of a randomly selected 16-byte value that has been base64-encoded.
    local key = base64.encode(randomChars(16))
    local client = HttpClient:new({
      url = self.url,
      method = 'GET',
      headers = {
        [HttpMessage.CONST.HEADER_USER_AGENT] = HttpMessage.CONST.DEFAULT_USER_AGENT,
        [HttpMessage.CONST.HEADER_CONNECTION] = CONST.CONNECTION_UPGRADE,
        [HttpMessage.CONST.HEADER_UPGRADE] = CONST.UPGRADE_WEBSOCKET,
        [CONST.HEADER_SEC_WEBSOCKET_VERSION] = CONST.WEBSOCKET_VERSION,
        [CONST.HEADER_SEC_WEBSOCKET_KEY] = key,
        [CONST.HEADER_SEC_WEBSOCKET_PROTOCOL] = self.protocols,
      }
    })
    return client:connect():next(function()
      return client:sendReceive()
    end):next(function(response)
      if response:getStatusCode() == HttpMessage.CONST.HTTP_SWITCHING_PROTOCOLS then
        if logger:isLoggable(logger.FINE) then
          logger:fine('webSocket:open() Switching protocols')
        end
        -- TODO Check accept key
        self.tcp = client:getTcpClient()
      else
        client:close()
        logger:warn('webSocket:open() bad status code '..tostring(response:getStatusCode()))
      end
    end, function(err)
      client:close()
      logger:warn('webSocket:open() error '..tostring(err))
    end)
  end

end)

--- @section end

--- WebSocket HTTP handler.
-- The open attribute must be set to a function that will be called with the new accepted WebSockets.
-- @param httpExchange the HTTP exchange to handle.
local function upgradeHandler(httpExchange)
  local request = httpExchange:getRequest()
  local response = httpExchange:getResponse()
  local context = httpExchange:getContext()
  local open = context:getAttribute('open')
  if logger:isLoggable(logger.FINE) then
    logger:fine('ws.upgradeHandler()')
    for name, value in pairs(request:getHeadersTable()) do
          logger:fine(tostring(name)..': "'..tostring(value)..'")')
    end
  end
  local headerConnection = string.lower(request:getHeader(HttpMessage.CONST.HEADER_CONNECTION) or '')
  local headerUpgrade = string.lower(request:getHeader(HttpMessage.CONST.HEADER_UPGRADE) or '')
  if string.find(headerConnection, string.lower(CONST.CONNECTION_UPGRADE)) and headerUpgrade == string.lower(CONST.UPGRADE_WEBSOCKET) then
      local headerSecWebSocketKey = request:getHeader(CONST.HEADER_SEC_WEBSOCKET_KEY)
      local headerSecWebSocketVersion = tonumber(request:getHeader(CONST.HEADER_SEC_WEBSOCKET_VERSION))
      if headerSecWebSocketKey and headerSecWebSocketVersion == CONST.WEBSOCKET_VERSION then
          local headerSecWebSocketProtocol = request:getHeader(CONST.HEADER_SEC_WEBSOCKET_PROTOCOL)
          local accept = context:getAttribute('accept')
          if type(accept) == 'function' and not accept(headerSecWebSocketProtocol, request) then
            response:setStatusCode(HttpMessage.CONST.HTTP_BAD_REQUEST, 'Upgrade Rejected')
            response:setBody('<p>Upgrade rejected.</p>')
          else
            response:setStatusCode(HttpMessage.CONST.HTTP_SWITCHING_PROTOCOLS, 'Switching Protocols')
            response:setHeader(HttpMessage.CONST.HEADER_CONNECTION, CONST.CONNECTION_UPGRADE)
            response:setHeader(HttpMessage.CONST.HEADER_UPGRADE, CONST.UPGRADE_WEBSOCKET)
            response:setHeader(CONST.HEADER_SEC_WEBSOCKET_ACCEPT, hashWebSocketKey(headerSecWebSocketKey))
            local protocol = context:getAttribute('protocol')
            if protocol then
                response:setHeader(CONST.HEADER_SEC_WEBSOCKET_PROTOCOL, protocol)
            end
            -- override HTTP client close
            local close = httpExchange.close
            function httpExchange:close()
              if logger:isLoggable(logger.FINE) then
                logger:fine('ws.upgradeHandler() close')
              end
              local tcpClient = self:removeClient()
              close(self)
              open(WebSocketBase:new(tcpClient))
            end
          end
        else
          response:setStatusCode(HttpMessage.CONST.HTTP_BAD_REQUEST, 'Bad Request')
          response:setBody('<p>Missing or invalid WebSocket headers.</p>')
      end
  else
      response:setStatusCode(HttpMessage.CONST.HTTP_BAD_REQUEST, 'Bad Request')
      response:setBody('<p>Missing or invalid connection headers.</p>')
  end
end

return {
  CONST = CONST,
  upgradeHandler = upgradeHandler,
  WebSocket = WebSocket
}
