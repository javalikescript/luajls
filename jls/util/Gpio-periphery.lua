
local class = require('jls.lang.class')
local logger = require('jls.lang.logger'):get(...)
local Promise = require('jls.lang.Promise')
local Worker = require('jls.util.Worker')
local Map = require('jls.util.Map')

local periphery = require('periphery')

return class.create('jls.util.GpioBase', function(gpio, super)

  function gpio:initialize()
    super.initialize(self)
    self.chip = 0
    self.gpios = {}
    self.pwms = {}
  end

  local function getGpioChip(self)
    return '/dev/gpiochip'..self.chip
  end

  function gpio:close()
    super.close(self)
    for _, g in pairs(self.gpios) do
      g:close()
    end
    self.gpios = {}
    for _, p in pairs(self.pwms) do
      p:close()
    end
    self.pwms = {}
    return self:readStop()
  end

  function gpio:cleanup()
  end

  local function getOrCreatePin(self, num, direction)
    local pin = self:getOrCreatePin(num)
    if direction then
      if pin.direction == nil then
        pin.direction = direction
      elseif pin.direction ~= direction then
        error('invalid direction '..tostring(pin.direction))
      end
    end
    return pin
  end

  local function getOrCreateGpio(self, num, direction)
    local g = self.gpios[num]
    if not g then
      local pin = getOrCreatePin(self, num, direction or 'in')
      g = periphery.GPIO(getGpioChip(self), num, pin.direction)
      if pin.bias then
        g.bias = pin.bias
      end
      self.gpios[num] = g
    end
    return g
  end

  local function getPwmChannel(num)
    if num > 1 then
      return num % 2 -- 18 is 0
    end
    return num
  end

  function gpio:setProperty(num, pin, name, value)
    return super.setProperty(self, num, pin, name, value):next(function()
      if string.find(name, '^pwm') then
        local channel = getPwmChannel(num)
        local pwm = self.pwms[channel]
        if pwm then
          if name == 'pwmDutyCycle' then
            pwm.duty_cycle = value
          elseif name == 'pwmFrequency' then
            pwm.frequency = value
          end
        else
          logger:fine('PWM %s/%s not found', num, channel)
        end
      else
        local g = self.gpios[num]
        if g then
          if name == 'direction' then
            g.direction = value
          elseif name == 'bias' then
            g.bias = value
          end
        else
          logger:fine('GPIO %s not found', num)
        end
      end
    end)
  end

  function gpio:read(num)
    local g = getOrCreateGpio(self, num, 'in')
    local value = g:read()
    return Promise.resolve(value)
  end

  function gpio:write(num, level)
    local g = getOrCreateGpio(self, num, 'out')
    g:write(level)
    return Promise.resolve()
  end

  function gpio:pwmStart(num)
    logger:finer('pwmStart(%s)', num)
    local channel = getPwmChannel(num)
    local pin = getOrCreatePin(self, num, 'out')
    local pwm = self.pwms[channel]
    if not pwm then
      logger:finer('create PWM %s with frequency %s duty cycle %s', channel, pin.pwmFrequency, pin.pwmDutyCycle)
      pwm = periphery.PWM(self.chip, channel)
      pwm.frequency = pin.pwmFrequency or 100
      pwm.duty_cycle = pin.pwmDutyCycle or 0
      self.pwms[channel] = pwm
    end
    pwm:enable()
    return Promise.resolve()
  end

  function gpio:pwmStop(num)
    logger:finer('pwmStop(%s)', num)
    local channel = getPwmChannel(num)
    local pwm = self.pwms[channel]
    if pwm then
      pwm:disable()
    end
    return Promise.resolve()
  end

  function gpio:readStop()
    local worker = self.worker
    if worker then
      self.worker = nil
      return worker:close()
    end
    return Promise.resolve()
  end

  function gpio:readStart(fn, ...)
    local nums = self:getStartList(fn, ...)
    logger:fine('readStart(%s)', table.concat(nums, ', '))
    local gpios = {}
    for _, num in ipairs(nums) do
      local g = Map.assign({
        path = getGpioChip(self),
        line = num,
        edge = 'both',
      }, self.pins[num])
      table.insert(gpios, g)
    end
    for _, g in ipairs(gpios) do
      local gg = self.gpios[g.line]
      -- get values
      if gg then
        gg:close()
      end
    end
    local worker = self.worker
    if worker then
      worker:close()
      self.worker = nil
    end
    worker = Worker:new(function(...)
      require('jls.util.Gpio-periphery')._workerFn(...)
    end, {
      chip = self.chip,
      gpios = gpios,
      timeout = 5000
    }, function(_, message)
      logger:fine('received from worker')
      fn(nil, message)
    end, {
      disableReceive = true
    })
    self.worker = worker
    return Promise.resolve()
  end

end, function(Gpio)

  function Gpio._workerFn(worker, options)
    logger:fine('initializing GPIO worker')
    local gpios = {}
    for index, g in ipairs(options.gpios) do
      gpios[index] = periphery.GPIO(g)
      logger:fine('GPIO %t', g)
    end
    local lastTimestamps = {}
    while worker:isConnected() do
      logger:finest('polling GPIO with timeout %dms...', options.timeout)
      local eventButtons = periphery.GPIO.poll_multiple(gpios, options.timeout)
      logger:finer('GPIO polled %l', eventButtons)
      for _, button in ipairs(eventButtons) do
        local e = button:read_event()
        if e then
          logger:fine('pin %d, edge: %s', button.line, e.edge)
          local lastTimestamp = lastTimestamps[button.line]
          lastTimestamps[button.line] = e.timestamp
          if not lastTimestamp or lastTimestamp > e.timestamp then
            lastTimestamp = 0
          end
          worker:postMessage({
            num = button.line,
            value = e.edge == 'rising',
            edge = e.edge,
            delay = e.timestamp - lastTimestamp,
            timestamp = e.timestamp
          })
        end
      end
    end
  end

end)
