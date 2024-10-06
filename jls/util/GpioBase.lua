--- Manages the Raspberry Pi General Purpose Input Outputs (GPIO).
-- The GPIO channels are identified by their Broadcom number.
-- The [pigpio](https://abyz.me.uk/rpi/pigpio/pigpiod.html) implementation expects the daemon to be available at localhost:8888.
-- @module jls.util.Gpio
-- @pragma nostrip

local class = require('jls.lang.class')
local logger = require('jls.lang.logger'):get(...)
local Promise = require('jls.lang.Promise')
local Map = require('jls.util.Map')
local List = require('jls.util.List')


--- This class represents a GPIO.
-- @type Gpio
return class.create(function(gpio)

  --- Creates a new GPIO controller.
  -- @function Gpio:new
  function gpio:initialize()
    self.pins = {}
  end

  --- Closes this GPIO instance.
  function gpio:close()
    self.pins = {}
    return Promise.resolve()
  end

  -- Set all channels used back to input with no pull up/down
  function gpio:cleanup()
    return Promise.resolve()
  end

  function gpio:closePin(num)
    self.pins[num] = nil
    return Promise.resolve()
  end

  function gpio:getOrCreatePin(num)
    if not(type(num) == 'number' and num >= 0 and num <= 53) then
      error('invalid pin number '..tostring(num))
    end
    local pin = self.pins[num]
    if not pin then
      pin = {}
      self.pins[num] = pin
    end
    return pin
  end

  local PROPERTIES = {
    direction = {type = 'string', set = List.asSet({'in', 'out'})},
    bias = {type = 'string', set = List.asSet({'default', 'pull_up', 'pull_down', 'disable'})},
    edge = {type = 'string', set = List.asSet({'none', 'rising', 'falling', 'both'})},
    pwmDutyCycle = {type = 'number', min = 0, max = 1},
    pwmFrequency = {type = 'number', min = 0},
  }

  local function normalizePropertyValue(name, value)
    local message
    local p = PROPERTIES[name]
    if p then
      if value ~= nil then
        if p.type and type(value) ~= p.type then
          message = string.format('bad type %s expected %s', type(value), p.type)
        elseif p.set and not p.set[value] then
          message = 'not in '..table.concat(Map.skeys(p.set), ',')
        elseif p.min and value < p.min or p.max and value > p.max then
          message = string.format('not between %s-%s', p.min or '', p.max or '')
        end
      end
    else
      error('invalid pin property name '..tostring(name))
    end
    if message then
      error(string.format('invalid value %s for property %s, %s', value, name, message))
    end
    return value
  end

  --- Sets a GPIO pin property value.
  -- @tparam number num The pin number from 0 to 53
  -- @tparam string name The property name to set
  -- @param value The property value to set
  function gpio:set(num, name, value)
    local pin = self:getOrCreatePin(num)
    if type(name) == 'table' then
      local p = Promise.resolve()
      for n, v in pairs(name) do
        p = p:next(function()
          return self:setProperty(num, pin, n, normalizePropertyValue(n, v))
        end)
      end
      return p
    end
    return self:setProperty(num, pin, name, normalizePropertyValue(name, value))
  end

  function gpio:setProperty(num, pin, name, value)
    logger:fine('setProperty(%s, %s, %s)', num, name, value)
    pin[name] = value
    return Promise.resolve()
  end

  function gpio:get(num, name)
    local pin = self.pins[num]
    if pin then
      return pin[name]
    end
  end

  --- Sets the internal bias pull/up down for a GPIO pin.
  -- @tparam number num The pin number
  -- @tparam[opt] string value The mode: default, pull_up, pull_down or disable
  function gpio:setBias(num, value)
    return self:set(num, 'bias', value)
  end

  --- Sets the direction for a GPIO pin.
  -- @tparam number num The pin number
  -- @tparam[opt] string value The direction: in or out
  function gpio:setDirection(num, value)
    return self:set(num, 'direction', value)
  end

  function gpio:setPwmDutyCycle(num, value)
    return self:set(num, 'pwmDutyCycle', value)
  end

  function gpio:setPwmFrequency(num, value)
    return self:set(num, 'pwmFrequency', value)
  end

  --- Reads a GPIO channel.
  -- @tparam number num The pin number
  -- @treturn jls.lang.Promise A promise that resolves to the pin value
  -- @function gpio:read
  gpio.read = class.notImplementedFunction

  --- Writes a GPIO channel.
  -- @tparam number num The pin number
  -- @tparam boolean level The channel level
  -- @treturn jls.lang.Promise A promise
  -- @function gpio:write
  gpio.write = class.notImplementedFunction

  -- @function gpio:pwmStart
  gpio.pwmStart = class.notImplementedFunction

  -- @function gpio:pwmStop
  gpio.pwmStop = class.notImplementedFunction

  --- Starts reading changes on pins.
  -- The function is called with two arguments, error and message.
  -- The message is a table containing the field: num, value, delay.
  -- Corresponding to the pin number, the pin value as a boolean, the delay since last change in milli-seconds.
  -- @tparam function fn The function to call on pin value modification
  -- @tparam number ... The pin numbers to monitor for modification
  -- @treturn jls.lang.Promise A promise
  -- @function gpio:readStart
  gpio.readStart = class.notImplementedFunction

  function gpio:getStartList(fn, ...)
    if type(fn) ~= 'function' then
      error('invalid function argument')
    end
    local values = {...}
    if #values == 0 then
      values = Map.keys(self.pins)
    end
    local nums = {}
    for _, num in ipairs(values) do
      local pin = self.pins[num]
      if pin and pin.direction == 'in' then
        table.insert(nums, num)
      end
    end
    if #nums == 0 then
      error('no pin to read')
    end
    return nums
  end

  --- Stops reading changes.
  -- @treturn jls.lang.Promise A promise
  function gpio:readStop()
    return Promise.resolve()
  end

end)
