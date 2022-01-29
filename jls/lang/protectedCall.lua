local logger = require('jls.lang.logger')
if logger:isLoggable(logger.FINE) or os.getenv('JLS_USE_XPCALL') ~= nil then
  return function(fn, ...)
    return xpcall(fn, debug.traceback, ...)
  end
end
return pcall
