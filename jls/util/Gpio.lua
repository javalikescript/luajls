local class = require('jls.lang.class')
local Promise = require('jls.lang.Promise')

local Pigs = require('jls.util.Pigs')

return class.create(function(gpio)

  function gpio:initialize()
    self.pigs = Pigs:new()
  end

  function gpio:close()
    if self.pigs then
      self.pigs:close()
      self.pigs = nil
    end
  end

  -- Set all used channels back to input without pull up/down
  function gpio:cleanup()
    -- TODO
  end

  local function parseDirection(direction)
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
    error('invalid pud')
  end

  local function parseLevel(level)
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
    error('invalid level')
  end

  function gpio:setup(channel, direction, pud)
    local d = parseDirection(direction)
    if pud then
      local p = parsePud(pud)
      return Promise.all({
        self.pigs:send(Pigs.CMD.MODES, channel, d),
        self.pigs:send(Pigs.CMD.PUD, channel, p)
      }):next(function(results)
        --return results[1] + results[2]
        return 0
      end)
    end
    return self.pigs:send(Pigs.CMD.MODES, channel, d)
  end

  function gpio:input(channel)
    return self.pigs:send(Pigs.CMD.READ, channel)
  end

  function gpio:output(channel, level)
    local l = parseLevel(level)
    return self.pigs:send(Pigs.CMD.WRITE, channel, l)
  end

  function gpio:pwm(channel, dutyCycle)
    local dc = parseDutyCycle(dutyCycle)
    return self.pigs:send(Pigs.CMD.PWM, channel, dc)
  end

end)
