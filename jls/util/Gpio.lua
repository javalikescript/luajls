--- Manages the Raspberry Pi General Purpose Input Outputs (GPIO).
-- The GPIO channels are identified by their Broadcom number.
-- The current implementation uses the [pigpio daemon](https://abyz.me.uk/rpi/pigpio/pigpiod.html).
-- @module jls.util.Gpio
-- @pragma nostrip

local class = require('jls.lang.class')
local logger = require('jls.lang.logger'):get(...)
local Promise = require('jls.lang.Promise')
local Pipe = require('jls.io.Pipe')
local FileDescriptor = require('jls.io.FileDescriptor')
local loader = require('jls.lang.loader')
local luvLib = loader.tryRequire('luv')

local Pigs = require('jls.util.Pigs')

local function parseDirection(direction)
  if type(direction) == 'number' then
    return direction
  end
  if direction == 'in' then
    return Pigs.MODES.IN
  elseif direction == 'out' then
    return Pigs.MODES.OUT
  end
  error('invalid direction')
end

local function parsePud(pud)
  if pud == 'off' then
    return Pigs.PUD.OFF
  elseif pud == 'down' then
    return Pigs.PUD.DOWN
  elseif pud == 'up' then
    return Pigs.PUD.UP
  end
  error('invalid pull up down')
end

local function parseLevel(level)
  if type(level) == 'boolean' then
    return level and 1 or 0
  end
  if type(level) == 'number' then
    return level
  end
  if level == 'off' then
    return 0
  elseif level == 'on' then
    return 1
  end
  error('invalid level')
end

local function parseDutyCycle(dutyCycle)
  if type(dutyCycle) == 'number' and dutyCycle >= 0 and dutyCycle <= 1 then
    return math.floor(dutyCycle * 255)
  end
  error('invalid duty cycle')
end


--- This class represents the GPIO.
-- @type Gpio
return class.create(function(gpio)

  --- Creates a new GPIO.
  -- @function Gpio:new
  function gpio:initialize()
    self.pigs = Pigs:new()
  end

  --- Closes this GPIO instance.
  function gpio:close()
    if not self.pigs then
      return Promise.resolve()
    end
    return Promise.allSettled({
      self:closeNotify(),
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

  --- Setup a GPIO channel.
  -- @tparam number channel The channel to setup from 0 to 53
  -- @tparam string direction The channel direction, in or out
  -- @treturn jls.lang.Promise A promise that resolves once the channel has been setup
  function gpio:setup(channel, direction)
    local d = parseDirection(direction)
    return self.pigs:send(Pigs.CMD.MODES, channel, d)
  end

  --- Sets the internal pull/up down for a GPIO channel.
  -- @tparam number channel The channel to set
  -- @tparam[opt] string pud The mode, up, down or off
  -- @treturn jls.lang.Promise A promise
  function gpio:setPullUpDown(channel, pud)
    local p = parsePud(pud or 'off')
    return self.pigs:send(Pigs.CMD.PUD, channel, p)
  end

  --- Reads a GPIO channel.
  -- @tparam number channel The channel to read
  -- @treturn jls.lang.Promise A promise that resolves to the channel level
  function gpio:read(channel)
    return self.pigs:send(Pigs.CMD.READ, channel):next(function(l)
      return l == 1
    end)
  end

  --- Writes a GPIO channel.
  -- @tparam number channel The channel to write
  -- @tparam boolean level The channel level
  -- @treturn jls.lang.Promise A promise
  function gpio:write(channel, level)
    local l = parseLevel(level)
    return self.pigs:send(Pigs.CMD.WRITE, channel, l)
  end

  --- Starts PWM.
  -- @tparam number channel The channel
  -- @tparam[opt] number dutyCycle The duty cycle from 0, off, to 1, on
  -- @treturn jls.lang.Promise A promise
  function gpio:setPwmDutyCycle(channel, dutyCycle)
    local dc = parseDutyCycle(dutyCycle or 0)
    return self.pigs:send(Pigs.CMD.PWM, channel, dc)
  end

  --- Closes notifications.
  -- @treturn jls.lang.Promise A promise
  function gpio:closeNotify()
    logger:finer('closeNotify()')
    return self:closePipeNotify():next(function()
      local h = self.nh
      if h then
        self.nh = nil
        return self.pigs:send(Pigs.CMD.NC, h)
      end
    end)
  end

  function gpio:setNotify(h)
    if h == self.nh then
      return Promise.resolve()
    end
    return self:closeNotify():next(function()
      self.nh = h
    end)
  end

  function gpio:openNotify()
    logger:finer('openNotify()')
    if self.nh then
      return Promise.resolve()
    end
    return self:closeNotify():next(function()
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

  function gpio:closePipeNotify()
    logger:finer('closePipeNotify()')
    local pipe = self.np
    if pipe then
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

  function gpio:openPipeNotify()
    logger:finer('openPipeNotify()')
    return self:openNotify():next(function()
      return self:closePipeNotify()
    end):next(function()
      local path = '/dev/pigpio'..tostring(self.nh)
      logger:fine('open pipe "%s"', path)
      local fd, err = FileDescriptor.openSync(path, 'r')
      if not fd then
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

  --- Starts notifications.  
  -- Note: Notifications require the `luv` module.
  -- @tparam function fn The function to call on channel modification
  -- @tparam number ... The channels to monitor for modification
  -- @treturn jls.lang.Promise A promise
  function gpio:notify(fn, ...)
    if type(fn) ~= 'function' then
      error('invalid function argument')
    end
    local channels = {...}
    local bits = 0
    for _, channel in ipairs(channels) do
      bits = bits | (1 << channel)
    end
    if bits == 0 then
      return self:closePipeNotify()
    end
    logger:fine('begin notify on 0x%x', bits)
    return self:openPipeNotify():next(function()
      return self.pigs:send(Pigs.CMD.NB, self.nh, bits)
    end):next(function()
      self.pigs:readStartPipe(self.np, function(err, level)
        if err then
          self:closeNotify()
        elseif level then
          for _, channel in ipairs(channels) do
            local value = (level & (1 << channel)) ~= 0
            fn(channel, value)
          end
        else
          self:closeNotify()
        end
      end)
    end)
  end

  gpio.input = gpio.read
  gpio.output = gpio.write
  gpio.pwm = gpio.setPwmDutyCycle
  gpio.pud = gpio.setPullUpDown

end)
