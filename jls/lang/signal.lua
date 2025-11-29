local function parseFlags(n)
  local flags, s = string.match(n, '^([%?!]*)(%w*)$')
  if not flags then
    error('invalid name')
  end
  return flags, s
end

local function hasFlag(flags, flag)
  return not not string.find(flags, flag, 1, true)
end

local hasLuv, luvLib = pcall(require, 'luv')
if hasLuv then
  return function(n, cb)
    local flags, s = parseFlags(n)
    local signal = luvLib.new_signal()
    luvLib.ref(signal)
    if hasFlag(flags, '!') then
      luvLib.signal_start_oneshot(signal, s, cb)
    else
      luvLib.signal_start(signal, s, cb)
    end
    return function()
      luvLib.signal_stop(signal)
      luvLib.unref(signal)
    end
  end
end

local class = require('jls.lang.class')
return function(n)
  local flags = parseFlags(n)
  if hasFlag(flags, '?') then
    return class.emptyFunction
  end
  error('not available')
end