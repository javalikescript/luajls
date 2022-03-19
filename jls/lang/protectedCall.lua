local logger = require('jls.lang.logger')
if logger:isLoggable(logger.FINE) or os.getenv('JLS_USE_XPCALL') or _G['JLS_USE_XPCALL'] then
  return function(fn, ...)
    if logger:isLoggable(logger.FINE) then
      return xpcall(fn, debug.traceback, ...)
    end
    return pcall(fn, ...)
  end
end
return pcall
