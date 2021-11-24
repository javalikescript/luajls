local luvLib = require('luv')

if type(luvLib.gettimeofday) ~= 'function' or type(luvLib.sleep) ~= 'function' then
  error('functions not available')
end

return {
  timems = function()
    local sec, usec = luvLib.gettimeofday()
    return sec * 1000 + usec // 1000
  end,
  gettimeofday = luvLib.gettimeofday,
  sleep = luvLib.sleep,
  getenv = luvLib.os_getenv,
  setenv = luvLib.os_setenv,
}
