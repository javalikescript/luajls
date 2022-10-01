
local os_time = os.time

return {
  timems = function()
    return os_time() * 1000
  end,
  gettimeofday = function()
    return os_time(), 0
  end,
  sleep = function(millis)
    local t = os_time() + (millis / 1000)
    while os_time() < t do end
  end,
  -- TODO move getenv/setenv to process or to env
  getenv = os.getenv,
  setenv = require('jls.lang.setenv'),
}
