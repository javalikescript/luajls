local class = require('jls.lang.class')
local logger = require('jls.lang.logger'):get(...)
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

return class.create(function(pigs)

  function pigs:initialize(port, addr)
    self.queue = {}
    self.index = 1
    self.dqIndex = 1
    self.format = '<I4I4I4I4' -- TODO detect endianness
    self.addr = addr or 'localhost'
    self.port = port or 8888
  end

  function pigs:connect()
    logger:finer('connect()')
    if self.client then
      return Promise.resolve()
    end
    logger:fine('connect(%s, %s)', self.addr, self.port)
    self.client = TcpSocket:new()
    return self.client:connect(self.addr, self.port):next(function()
      logger:fine('connected')
      self.client:readStart(StreamHandler.block(function(err, data)
        logger:fine('read %s, %x', err, data)
        if err then
          self:close(err)
        elseif data then
          local cb = self.queue[self.dqIndex]
          self.queue[self.dqIndex] = nil
          self.dqIndex = self.dqIndex + 1
          local cmd, p1, p2, res = string.unpack(self.format, data)
          logger:fine('recv: %s, %s, %s', cmd, p1, p2, res)
          cb(nil, res)
        else
          self:close()
        end
      end, string.packsize(self.format)))
    end)
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

  function pigs:send(cmd, p1, p2)
    local data = string.pack(self.format, cmd, p1 or 0, p2 or 0, 0)
    logger:fine('send(%s, %s, %s)', cmd, p1, p2)
    return self:connect():next(function()
      logger:fine('write(%x)', data)
      return self.client:write(data)
    end):next(function()
      local promise, cb = Promise.withCallback()
      self.queue[self.index] = cb
      self.index = self.index + 1
      return promise
    end)
  end

end, function(Pigs)

  Pigs.CMD = CMD
  Pigs.MODES = MODES
  Pigs.PUD = PUD

end)
