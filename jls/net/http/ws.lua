--- This module provide classes to work with WebSocket.
-- @module jls.net.http.ws
-- @pragma nostrip

local class = require('jls.lang.class')
local Promise = require('jls.lang.Promise')
local logger = require('jls.lang.logger')
local StringBuffer = require('jls.lang.StringBuffer')
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

local math_random = math.random
local string_char = string.char
local string_byte = string.byte

local function randomChars(len)
  local buffer = ''
  for _ = 1, len do
    buffer = buffer..string_char(math_random(0, 255))
  end
  return buffer
end

local function generateMask()
  return string_char(math_random(1, 255), math_random(1, 255), math_random(1, 255), math_random(1, 255))
end

local function applyMask(mask, payload)
  if payload == '' then
    return ''
  end
  return string.gsub(payload, '(..?.?.?)', function(value)
    local len = #value
    if len == 4 then
      local a, b, c, d = string_byte(value, 1, len)
      local e, f, g, h = string_byte(mask, 1, len)
      return string_char(a ~ e, b ~ f, c ~ g, d ~ h)
    elseif len == 3 then
      local a, b, c = string_byte(value, 1, len)
      local e, f, g = string_byte(mask, 1, len)
      return string_char(a ~ e, b ~ f, c ~ g)
    elseif len == 2 then
      local a, b = string_byte(value, 1, len)
      local e, f = string_byte(mask, 1, len)
      return string_char(a ~ e, b ~ f)
    elseif len == 1 then
      local a = string_byte(value, 1)
      local e = string_byte(mask, 1)
      return string_char(a ~ e)
    end
  end)
end

local function read2BytesHeader(buffer)
  local b1, b2 = string_byte(buffer, 1, 2)
  local fin = (b1 & 0x80) == 0x80
  local rsv = (b1 >> 4) & 0x07
  local opcode = b1 & 0x0f
  local mask = (b2 & 0x80) == 0x80
  local len = b2 & 0x7f
  if logger:isLoggable(logger.FINEST) then
    logger:finest('WebSocket readHeader(), fin: '..tostring(fin)..', rsv: '..tostring(rsv)..', opcode: '..tostring(opcode)..', mask: '..tostring(mask)..', len: '..tostring(len))
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

local function formatFrame(fin, opcode, mask, payload)
  if not payload then
    payload = ''
  end
  local b1 = 0
  if fin then
    b1 = 0x80
  end
  b1 = b1 + (opcode & 0x0f)
  local payload_length = #payload
  local len, size_length
  if payload_length < 126 then
    len = payload_length
    size_length = 0
  elseif payload_length < 65536 then
    len = 126
    size_length = 2
  else
    len = 127
    size_length = 8
  end
  local b2 = 0
  if mask then
    b2 = 0x80
  end
  b2 = b2 + (len & 0x7f)
  local hdr_size = ''
  for i = 1, size_length do
    hdr_size = string_char(payload_length & 0xff)..hdr_size
    payload_length = payload_length // 256
  end
  local header = string_char(b1, b2)..hdr_size
  if mask then
    local mask_chars = generateMask()
    return header..mask_chars..applyMask(mask_chars, payload)
  end
  return header..payload
end

--- The WebSocketBase class represents the base class for WebSocket.
-- @type WebSocketBase
local WebSocketBase = class.create(function(webSocketBase)

  --- Creates a new WebSocket.
  -- @tparam[opt] boolean client true to indicate that the websocket is the client.
  -- @function WebSocketBase:new
  function webSocketBase:initialize(tcp, client)
    self.tcp = tcp
    -- A client MUST mask all frames that it sends to the server
    -- A server MUST NOT mask any frames that it sends to the client
    self.mask = client == true
    self.contOpCode = 0
    self.contBuffer = StringBuffer:new()
  end

  --- Closes this WebSocket.
  -- @tparam function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the WebSocket is closed.
  function webSocketBase:close(callback)
    if self.tcp then
      local tcp = self.tcp
      self.tcp = nil
      return tcp:close(callback)
    end
    if callback == nil then
      return Promise.resolve()
    end
    if callback then
      callback()
    end
  end

  --- Called when this WebSocket has been closed due to an error,
  -- such as when some data couldn't be received or sent.
  -- @param reason the error reason.
  function webSocketBase:onError(reason)
    if logger:isLoggable(logger.FINE) then
      logger:fine('webSocketBase:onError("'..tostring(reason)..'")')
    end
  end

  function webSocketBase:raiseError(reason)
    self:close(false)
    self:onClose()
    self:onError(reason)
  end

  --- Called when a text message is received on this WebSocket.
  -- @tparam string message the text message.
  function webSocketBase:onTextMessage(message)
    if logger:isLoggable(logger.FINE) then
      logger:fine('webSocketBase:onTextMessage("'..tostring(message)..'")')
    end
  end

  --- Called when a binary message is received on this WebSocket.
  -- @tparam string message the binary message.
  function webSocketBase:onBinaryMessage(message)
    if logger:isLoggable(logger.FINE) then
      logger:fine('webSocketBase:onBinaryMessage()')
    end
  end

  function webSocketBase:onPong(data)
    if logger:isLoggable(logger.FINE) then
      logger:fine('webSocketBase:onPong("'..tostring(data)..'")')
    end
  end

  --- Called when this WebSocket has been closed.
  function webSocketBase:onClose()
    if logger:isLoggable(logger.FINE) then
      logger:fine('webSocketBase:onClose()')
    end
  end

  function webSocketBase:onReadFrameFin(opcode, payload)
    if opcode == CONST.OP_CODE_TEXT_FRAME then
      self:onTextMessage(payload)
    elseif opcode == CONST.OP_CODE_BINARY_FRAME then
      self:onBinaryMessage(payload)
    end
  end

  function webSocketBase:handleExtension(fin, opcode, payload, rsv)
    if rsv == 0 then
      return payload
    end
    return nil
  end

  function webSocketBase:onReadFrame(fin, opcode, payload, rsv)
    if logger:isLoggable(logger.FINER) then
      logger:finer('webSocketBase:onReadFrame('..tostring(fin)..', '..tostring(opcode)..', '..tostring(#payload)..', '..tostring(rsv)..')')
    end
    local appData = self:handleExtension(fin, opcode, payload, rsv)
    if not appData then
      self:raiseError('unsupported extension, '..tostring(rsv))
      return
    end
    if opcode == CONST.OP_CODE_CONTINUATION then
      self.contBuffer:append(appData)
      if fin then
        self:onReadFrameFin(self.contOpCode, self.contBuffer:toString())
        self.contBuffer:clear()
        self.contOpCode = 0
      end
    elseif opcode == CONST.OP_CODE_TEXT_FRAME or opcode == CONST.OP_CODE_BINARY_FRAME then
      if fin then
        self:onReadFrameFin(opcode, appData)
      else
        self.contOpCode = opcode
        self.contBuffer:clear()
        self.contBuffer:append(appData)
      end
    elseif opcode == CONST.OP_CODE_PING then
      self:sendFrame(true, CONST.OP_CODE_PONG, self.mask, appData)
    elseif opcode == CONST.OP_CODE_PONG then
      self:onPong(appData)
    elseif opcode == CONST.OP_CODE_CLOSE then
      self:close(false)
      self:onClose()
    else
      self:raiseError('unsupported op code: '..tostring(opcode))
    end
  end

  --- Stops receiving messages on this WebSocket.
  function webSocketBase:readStop()
    if self.tcp then
      self.tcp:readStop()
    end
  end

  --- Starts receiving messages on this WebSocket.
  function webSocketBase:readStart()
    -- stream implementation that buffers and splits packets
    local buffer = ''
    return self.tcp:readStart(function(err, data)
      if err then
        self:raiseError(err)
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
                  len = (len * 256) + string_byte(buffer, i)
              end
              idx = idx + sizeLength
          end
          local maskChars
          if maskLength > 0 then
              maskChars = string.sub(buffer, idx, idx + maskLength - 1)
              idx = idx + maskLength
          end
          local frameLength = headerLength + len
          if bufferLength < frameLength then
            break
          end
          local payload = string.sub(buffer, idx, idx + len - 1)
          if maskChars then
              payload = applyMask(maskChars, payload)
          end
          if bufferLength == frameLength then
            buffer = ''
          else
            buffer = string.sub(buffer, frameLength + 1)
          end
          self:onReadFrame(fin, opcode, payload, rsv)
        end
      else
        self:raiseError('end of stream')
      end
    end)
  end

  function webSocketBase:sendFrame(fin, opcode, mask, payload, callback)
    if logger:isLoggable(logger.FINER) then
      logger:finer('webSocketBase:sendFrame('..tostring(fin)..', '..tostring(opcode)..', '..tostring(mask)..')')
    end
    local frame = formatFrame(fin, opcode, mask, payload)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('webSocketBase:sendFrame() '..hex.encode(frame))
    end
    local cb, d = Promise.ensureCallback(callback)
    self.tcp:write(frame, function(err)
      if err then
        self:raiseError(err)
      end
      if cb then
        cb(err)
      end
    end)
    return d
  end

  --- Sends a message on this WebSocket.
  -- @tparam string message the message to send.
  -- @tparam function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the data has been written.
  function webSocketBase:sendTextMessage(message, callback)
    if logger:isLoggable(logger.FINER) then
      logger:finer('webSocketBase:sendTextMessage("'..tostring(message)..'")')
    end
    return self:sendFrame(true, CONST.OP_CODE_TEXT_FRAME, self.mask, tostring(message), callback)
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
    super.initialize(self, nil, true)
    self.url = url
    self.protocols = protocols
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
      if response:getStatusCode() ~= HttpMessage.CONST.HTTP_SWITCHING_PROTOCOLS then
        client:close()
        return Promise.reject('Bad status code: '..tostring(response:getStatusCode()))
      end
      if logger:isLoggable(logger.FINE) then
        logger:fine('webSocket:open() Switching protocols')
      end
      -- TODO Check accept key
      self.tcp = client:getTcpClient()
    end, function(reason)
      client:close()
      logger:fine('webSocket:open() error: "'..tostring(reason)..'"')
      return Promise.reject(reason)
    end)
  end

end)

--- @section end

local function upgrade(exchange, open, accept, protocol)
  local request = exchange:getRequest()
  local response = exchange:getResponse()
  if logger:isLoggable(logger.FINER) then
    logger:finer('ws.upgradeHandler()')
    for name, value in pairs(request:getHeadersTable()) do
      logger:finer(' '..tostring(name)..': "'..tostring(value)..'"')
    end
  end
  local headerConnection = string.lower(request:getHeader(HttpMessage.CONST.HEADER_CONNECTION) or '')
  local headerUpgrade = string.lower(request:getHeader(HttpMessage.CONST.HEADER_UPGRADE) or '')
  if string.find(headerConnection, string.lower(CONST.CONNECTION_UPGRADE)) and headerUpgrade == string.lower(CONST.UPGRADE_WEBSOCKET) then
    local headerSecWebSocketKey = request:getHeader(CONST.HEADER_SEC_WEBSOCKET_KEY)
    local headerSecWebSocketVersion = tonumber(request:getHeader(CONST.HEADER_SEC_WEBSOCKET_VERSION))
    if headerSecWebSocketKey and headerSecWebSocketVersion == CONST.WEBSOCKET_VERSION then
      local headerSecWebSocketProtocol = request:getHeader(CONST.HEADER_SEC_WEBSOCKET_PROTOCOL)
      if type(accept) == 'function' and not accept(headerSecWebSocketProtocol, exchange) then
        -- TODO Check if response has been set
        response:setStatusCode(HttpMessage.CONST.HTTP_BAD_REQUEST, 'Upgrade Rejected')
        response:setBody('<p>Upgrade rejected.</p>')
      else
        response:setStatusCode(HttpMessage.CONST.HTTP_SWITCHING_PROTOCOLS, 'Switching Protocols')
        response:setHeader(HttpMessage.CONST.HEADER_CONNECTION, CONST.CONNECTION_UPGRADE)
        response:setHeader(HttpMessage.CONST.HEADER_UPGRADE, CONST.UPGRADE_WEBSOCKET)
        response:setHeader(CONST.HEADER_SEC_WEBSOCKET_ACCEPT, hashWebSocketKey(headerSecWebSocketKey))
        if protocol then
          response:setHeader(CONST.HEADER_SEC_WEBSOCKET_PROTOCOL, protocol)
        end
        function exchange:prepareResponseHeaders()
        end
        -- override HTTP client close
        local close = exchange.close
        function exchange:close()
          if logger:isLoggable(logger.FINER) then
            logger:finer('ws.upgradeHandler() close exchange')
          end
          local tcpClient = self:removeClient()
          close(self)
          if logger:isLoggable(logger.FINER) then
            logger:finer('ws.upgradeHandler() open websocket')
          end
          open(WebSocketBase:new(tcpClient), exchange)
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

--- WebSocket HTTP upgrade handler.
-- The open attribute must be set to a function that will be called with the new accepted WebSockets.
-- @param exchange the HTTP exchange to handle.
-- @function upgradeHandler
local function upgradeHandler(exchange)
  local context = exchange:getContext()
  local open = context:getAttribute('open')
  local accept = context:getAttribute('accept')
  local protocol = context:getAttribute('protocol')
  upgrade(exchange, open, accept, protocol)
end

--- An HTTP handler to upgrade the connection and accept web sockets.
-- @type WebSocketUpgradeHandler
local WebSocketUpgradeHandler = class.create('jls.net.http.HttpHandler', function(webSocketUpgradeHandler)
  --- Creates a new WebSocketUpgradeHandler.
  -- @function WebSocketUpgradeHandler:new
  -- @tparam[opt] string protocol The protocol.
  -- @return a new WebSocketUpgradeHandler
  function webSocketUpgradeHandler:initialize(protocol)
    self.openFn = function(...)
      self:onOpen(...)
    end
    self.acceptFn = function(...)
      return self:accept(...)
    end
    self.protocol = protocol
  end
  function webSocketUpgradeHandler:handle(exchange)
    upgrade(exchange, self.openFn, self.acceptFn, self.protocol)
  end
  function webSocketUpgradeHandler:setProtocol(protocol)
    self.protocol = protocol
  end
  function webSocketUpgradeHandler:onOpen(webSocket, exchange)
    if logger:isLoggable(logger.FINE) then
      logger:fine('webSocketUpgradeHandler:onOpen() closing')
    end
    webSocket:close(false)
  end
  function webSocketUpgradeHandler:accept(protocol, request)
    return true
  end
end)

return {
  CONST = CONST,
  upgradeHandler = upgradeHandler,
  WebSocketUpgradeHandler = WebSocketUpgradeHandler,
  WebSocket = WebSocket,
  randomChars = randomChars,
  generateMask = generateMask,
  applyMask = applyMask,
}
