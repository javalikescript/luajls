local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local streams = require('jls.io.streams')

return require('jls.lang.class').create(streams.StreamHandler, function(headerStreamHandler, super)

  function headerStreamHandler:initialize(message, size)
    super.initialize(self)
    self.message = message
    self.maxLineLength = size or 2048
    self.firstLine = true
  end

  function headerStreamHandler:onData(line)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('headerStreamHandler:onData("'..tostring(line)..'")')
    end
    if not self.onCompleted then
      if logger:isLoggable(logger.WARN) then
        logger:warn('HeaderStreamHandler receive data after read completed')
        logger:traceback()
      end
      error('Data after read completed')
    end
    if not line then
      if self.firstLine then
        self:onError('No header')
      else
        self:onError('Unexpected end of header')
      end
      return false
    end
    -- decode header
    local l = string.len(line)
    if l >= self.maxLineLength then
      self:onError('Too long header line (max is '..tostring(self.maxLineLength)..')')
    elseif l == 0 then
      self:onCompleted()
    else
      if self.firstLine then
        self.message:setLine(line)
        if string.find(self.message:getVersion(), '^HTTP/') then
          self.firstLine = false
          return true
        else
          self:onError('Bad HTTP request line (Invalid version in "'..line..'")')
        end
      else
        if self.message:parseHeaderLine(line) then
          return true
        else
          self:onError('Bad HTTP request header ("'..line..'")')
        end
      end
    end
    return false -- stop
  end

  function headerStreamHandler:onError(err)
    if self.onCompleted then
      self:onCompleted(err or 'Unknown error')
    else
      logger:warn('HeaderStreamHandler in error, due to '..tostring(err))
      error('Error after read completed')
    end
  end

  function headerStreamHandler:read(tcpClient, buffer)
    if logger:isLoggable(logger.FINE) then
      logger:fine('headerStreamHandler:read(?, #'..tostring(buffer and #buffer)..')')
    end
    if self.onCompleted then
      error('Read in progress')
    end
    return Promise:new(function(resolve, reject)
      local c
      local partHandler = streams.ChunkedStreamHandler:new(self, '\r\n', self.maxLineLength)
      function self:onCompleted(err)
        if logger:isLoggable(logger.FINE) then
          logger:fine('headerStreamHandler:read() onCompleted('..tostring(err)..')')
        end
        self.onCompleted = nil
        if c then
          c:readStop()
        end
        if err then
          reject(err)
        else
          resolve(partHandler:getBuffer())
        end
      end
      if buffer then
        partHandler:onData(buffer)
      end
      if self.onCompleted then
        c = tcpClient
        c:readStart(partHandler)
      end
    end)
  end
end)
