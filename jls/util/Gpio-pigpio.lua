local class = require('jls.lang.class')
local logger = require('jls.lang.logger'):get(...)
local Promise = require('jls.lang.Promise')
local Pipe = require('jls.io.Pipe')
local FileDescriptor = require('jls.io.FileDescriptor')

local loader = require('jls.lang.loader')
local luvLib = loader.tryRequire('luv')

local Pigs = require('jls.util.Pigs')

local VALUE_MAP = {
  direction = {
    ['in'] = Pigs.MODES.IN,
    out = Pigs.MODES.OUT,
  },
  bias = {
    default = Pigs.PUD.OFF,
    pull_up = Pigs.PUD.UP,
    pull_down = Pigs.PUD.DOWN,
    disable = Pigs.PUD.OFF,
  },
}


return class.create('jls.util.GpioBase', function(gpio, super)

  --- Creates a new GPIO.
  -- @function Gpio:new
  function gpio:initialize()
    super.initialize(self)
    self.pigs = Pigs:new()
  end

  --- Closes this GPIO instance.
  function gpio:close()
    super.close(self)
    if not self.pigs then
      return Promise.resolve()
    end
    return Promise.allSettled({
      self:readStop(),
      self:cleanup()
    }):next(function()
      self.pigs:close()
      self.pigs = nil
    end)
  end

  -- Set all channels used back to input with no pull up/down
  function gpio:cleanup()
    -- TODO
    return Promise.resolve()
  end

  local function setPwmDutyCycle(self, num, value)
    return self.pigs:send(Pigs.CMD.PWM, num, math.floor((value or 0) * 255))
  end

  function gpio:setProperty(num, pin, name, value)
    return super.setProperty(self, num, pin, name, value):next(function()
      if name == 'direction' then
        return self.pigs:send(Pigs.CMD.MODES, num, VALUE_MAP.direction[value])
      elseif name == 'bias' then
        return self.pigs:send(Pigs.CMD.PUD, num, VALUE_MAP.bias[value])
      elseif name == 'pwmDutyCycle' and pin.pwmEnabled then
        return setPwmDutyCycle(self, num, value)
      elseif name == 'pwmFrequency' then
        return self.pigs:send(Pigs.CMD.PFS, num, value)
      end
    end)
  end

  function gpio:read(num)
    return self.pigs:send(Pigs.CMD.READ, num):next(function(l)
      return l == 1
    end)
  end

  function gpio:write(num, level)
    local l = level and 1 or 0
    return self.pigs:send(Pigs.CMD.WRITE, num, l)
  end

  function gpio:pwmStart(num)
    local pin = self:getOrCreatePin(num)
    if pin.pwmEnabled then
      return Promise.resolve()
    end
    pin.pwmEnabled = true
    return setPwmDutyCycle(self, num, pin.pwmDutyCycle or 0)
  end

  function gpio:pwmStop(num)
    local pin = self:getOrCreatePin(num)
    if not pin.pwmEnabled then
      return Promise.resolve()
    end
    pin.pwmEnabled = false
    return setPwmDutyCycle(self, num, 0)
  end

  function gpio:setNotify(h)
    if h == self.nh then
      return Promise.resolve()
    end
    return self:readStop():next(function()
      self.nh = h
    end)
  end

  function gpio:openNotify()
    if self.nh then
      logger:finest('openNotify() => %s', self.nh)
      return Promise.resolve()
    end
    logger:finer('openNotify()')
    return self:readStop():next(function()
      logger:finer('requests a free notification handle')
      return self.pigs:send(Pigs.CMD.NO)
    end):next(function(h)
      logger:fine('notification handle is %s', h)
      if not h or h < 0 then
        return Promise.reject()
      end
      self.nh = h
      if h > 0 then
        logger:fine('closing handles < %d', h)
        local l = {}
        for i = 0, h - 1 do
          table.insert(l, self.pigs:send(Pigs.CMD.NC, i))
        end
        return Promise.allSettled(l)
      end
    end)
  end

  function gpio:closePipe()
    logger:finest('closePipe()')
    local pipe = self.np
    if pipe then
      logger:fine('closing pipe')
      self.np = nil
      pipe:close(false)
    end
    local fd = self.nf
    if fd then
      self.nf = nil
      fd:closeSync()
    end
    return Promise.resolve()
  end

  function gpio:openPipe()
    logger:finer('openPipe()')
    return self:openNotify():next(function()
      return self:closePipe()
    end):next(function()
      local path = '/dev/pigpio'..tostring(self.nh)
      logger:fine('open pipe "%s"', path)
      local fd, err = FileDescriptor.openSync(path, 'r')
      if not fd then
        logger:fine('cannot open pipe "%s"', path)
        return Promise.reject(err)
      end
      if type(fd.fd) ~= 'number' or luvLib.guess_handle(fd.fd) ~= 'pipe' then
        fd:closeSync()
        return Promise.reject('invalid pipe')
      end
      self.nf = fd
      local pipe = Pipe:new()
      pipe:open(fd.fd)
      self.np = pipe
    end)
  end

  function gpio:readStop()
    logger:finer('readStop()')
    return self:closePipe():next(function()
      local h = self.nh
      if h then
        self.nh = nil
        return self.pigs:send(Pigs.CMD.NC, h)
      end
    end)
  end

  function gpio:readStart(fn, ...)
    logger:finer('readStart()')
    local lines = self:getStartList(fn, ...)
    local bits = 0
    local lastTicks = {}
    for i, line in ipairs(lines) do
      bits = bits | (1 << line)
      lastTicks[i] = 0
    end
    if bits == 0 then
      return self:closePipe()
    end
    local lastLevel = 0
    return self.pigs:send(Pigs.CMD.BR1):next(function(level)
      logger:fine('bank 1 level is 0x%x', level)
      lastLevel = level
      return self:openPipe()
    end):next(function()
      logger:fine('begin notify on %s, 0x%x', self.nh, bits)
      return self.pigs:send(Pigs.CMD.NB, self.nh, bits)
    end):next(function()
      logger:fine('starting pipe reading')
      self.pigs:readStartPipe(self.np, function(err, level, tick, seqno)
        if err then
          self:readStop()
        elseif level then
          local changedLevel = level ~ lastLevel
          lastLevel = level
          for i, line in ipairs(lines) do
            local lineBit = 1 << line
            if (changedLevel & lineBit) ~= 0 then
              local lastTick = lastTicks[i]
              lastTicks[i] = tick
              if lastTick > tick then
                lastTick = tick
              end
              local value = (level & lineBit) ~= 0
              fn(nil, {
                num = line,
                value = value,
                delay = tick - lastTick, -- µs
              })
            end
          end
        else
          self:readStop()
        end
      end)
    end)
  end

  gpio.input = gpio.read
  gpio.output = gpio.write
  gpio.pwm = gpio.setPwmDutyCycle
  gpio.pud = gpio.setBias
  gpio.setPullUpDown = gpio.setBias

end)
