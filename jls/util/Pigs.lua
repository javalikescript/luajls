
local class = require('jls.lang.class')
local logger = require('jls.lang.logger'):get(...)
local Exception = require('jls.lang.Exception')
local Promise = require('jls.lang.Promise')
local TcpSocket = require('jls.net.TcpSocket')
local StreamHandler = require('jls.io.StreamHandler')

local CMD = {
  MODES = 0,
  MODEG = 1,
  PUD = 2,
  READ = 3,
  WRITE = 4,
  PWM = 5,
  PRS = 6,
  PFS = 7,
  BR1 = 10,
  BR2 = 11,
  PRG = 22,
  PFG = 23,
  PRRG = 24,
  GDC = 83,
  NO = 18,
  NB = 19,
  NP = 20,
  NC = 21,
  HC = 85,
  HP = 86,
}

local MODES = {
  IN = 0,
  OUT = 1,
  ALT0 = 4,
  ALT1 = 5,
  ALT2 = 6,
  ALT3 = 7,
  ALT4 = 3,
  ALT5 = 2,
}

local PUD = {
  OFF = 0,
  DOWN = 1,
  UP = 2,
}

local NTFY_FLAGS = {
  EVENT = 1 << 7,
  ALIVE = 1 << 6,
  WDOG = 1 << 5,
}

local CMD_FORMAT = 'I4I4I4I4' -- cmd, p1, p2, p3/res
local REPORT_FORMAT = 'I2I2I4I4' -- seqno, flags, tick, level

return class.create(function(pigs)

  function pigs:initialize(port, addr)
    self.queue = {}
    self.index = 1
    self.dqIndex = 1
    self.endian = '='
    self.addr = addr or 'localhost'
    self.port = port or 8888
  end

  function pigs:connect()
    logger:finer('connect()')
    if self.connectPromise then
      return self.connectPromise
    end
    if self.client then
      return Promise.resolve()
    end
    logger:fine('connecting to %s:%s', self.addr, self.port)
    local format = self.endian..CMD_FORMAT
    self.client = TcpSocket:new()
    self.connectPromise = self.client:connect(self.addr, self.port):next(function()
      logger:fine('connected')
      self.connectPromise = nil
      if not self.client then
        return Promise.reject()
      end
      self.client:readStart(StreamHandler.block(function(err, data)
        logger:fine('socket read %s, %x', err, data)
        if err then
          self:close(err)
        elseif data then
          local cb = self.queue[self.dqIndex]
          self.queue[self.dqIndex] = nil
          self.dqIndex = self.dqIndex + 1
          local cmd, p1, p2, res = string.unpack(format, data)
          logger:fine('socket recv: %s, %s, %s', cmd, p1, p2, res)
          cb(nil, res)
        else
          self:close()
        end
      end, string.packsize(format)))
    end)
    return self.connectPromise
  end

  function pigs:close(reason)
    logger:finer('close()')
    if self.client then
      self.client:close()
      self.client = nil
      for _, cb in ipairs(self.queue) do
        cb(reason or 'closed')
      end
      self.queue = {}
    end
  end

  function pigs:enqueueCallback()
    local promise, cb = Promise.withCallback()
    self.queue[self.index] = cb
    self.index = self.index + 1
    return promise
  end

  function pigs:send(cmd, p1, p2)
    local data = string.pack(self.endian..CMD_FORMAT, cmd, p1 or 0, p2 or 0, 0)
    logger:fine('send(%s, %s, %s)', cmd, p1, p2)
    return self:connect():next(function()
      logger:fine('write(%x)', data)
      return self.client:write(data)
    end):next(function()
      return self:enqueueCallback()
    end)
  end

  function pigs:readStartPipe(pipe, cb)
    local reportFormat = self.endian..REPORT_FORMAT
    pipe:readStart(StreamHandler.block(function(err, data)
      logger:fine('pipe read %s, %x', err, data)
      if err then
        pipe:readStop()
        cb(err)
      elseif data then
        local seqno, flags, tick, level = string.unpack(reportFormat, data)
        logger:fine('pipe report: %s, %s, %s, %s', seqno, flags, tick, level)
        if flags == 0 then
          cb(nil, level, tick, seqno)
        end
      else
        pipe:readStop()
        cb('closed')
      end
    end, string.packsize(reportFormat)))
  end

end, function(Pigs)

  Pigs.CMD = CMD
  Pigs.MODES = MODES
  Pigs.PUD = PUD
  Pigs.CMD_FORMAT = CMD_FORMAT
  Pigs.REPORT_FORMAT = REPORT_FORMAT

end)
