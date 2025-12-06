local logger = require('jls.lang.logger'):get(...)
local Promise = require('jls.lang.Promise')
local ChunkedStreamHandler = require('jls.io.streams.ChunkedStreamHandler')

return require('jls.lang.class').create('jls.io.StreamHandler', function(headerStreamHandler, super)

  function headerStreamHandler:initialize(message, maxLineLength, maxSize)
    super.initialize(self)
    self.message = message
    self.maxLineLength = maxLineLength or 4096
    self.maxSize = maxSize or self.maxLineLength * 8
    self.size = 0
    self.firstLine = true
    self.errorStatus = nil
  end

  function headerStreamHandler:isEmpty()
    return self.firstLine
  end

  function headerStreamHandler:getErrorStatus()
    return self.errorStatus
  end

  function headerStreamHandler:onData(line)
    logger:finest('onData("%s")', line)
    if not self.onCompleted then
      if line then
        -- SLA TODO decrease log level and/or check data
        logger:warn('HeaderStreamHandler received data after read completed (%s)', line)
        --error('Data after read completed')
      end
      return
    end
    if not line then
      if self.firstLine then
        self:onError('No header line')
      else
        self:onError('Unexpected end of headers')
      end
      return
    end
    -- decode header
    local l = string.len(line)
    self.size = self.size + l
    if l >= self.maxLineLength then
      logger:fine('onData() too long header is "%s"', line)
      self:onError('Too long header line '..tostring(l)..' (max is '..tostring(self.maxLineLength)..')', 413)
    elseif self.size >= self.maxSize then
      self:onError('Too much headers '..tostring(self.size)..' (max is '..tostring(self.maxSize)..')', 413)
    elseif l == 0 then
      self:onCompleted()
    else
      if self.firstLine then
        self.firstLine = false
        if not self.message:parseLine(line) then
          self:onError('Bad HTTP start line "'..line..'"', 400)
        end
      else
        if not self.message:parseHeaderLine(line) then
          self:onError('Bad HTTP request header ("'..line..'")', 400)
        end
      end
    end
  end

  function headerStreamHandler:onError(err, statusCode)
    if self.onCompleted then
      if statusCode then
        self.errorStatus = statusCode
      end
      self:onCompleted(err or 'Unknown error')
    else
      logger:warn('HeaderStreamHandler in error, due to %s', err)
      error('Error after read completed')
    end
  end

  function headerStreamHandler:read(stream, buffer)
    logger:finer('read(?, #%l)', buffer)
    if self.onCompleted then
      error('Read in progress')
    end
    return Promise:new(function(resolve, reject)
      local s
      local partHandler = ChunkedStreamHandler:new(self, '\r\n', true, self.maxLineLength, '')
      function self:onCompleted(err)
        logger:finer('read() onCompleted(%s)', err)
        self.onCompleted = nil
        if s then
          s:readStop()
        end
        if err then
          reject(err)
        else
          if logger:isLoggable(logger.FINER) then
            logger:finer('headers are\r\n%s', self.message:getRawHeaders())
          end
          resolve(partHandler:getBuffer())
        end
      end
      if buffer then
        partHandler:onData(buffer)
      end
      if self.onCompleted then
        s = stream
        s:readStart(partHandler)
      end
    end)
  end

end)
