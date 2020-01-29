local luaSocketLib = require('socket')

return {
  timems = function()
    return math.floor(luaSocketLib.gettime() * 1000)
  end,
  gettimeofday = function()
    local t = luaSocketLib.gettime()
    local sec = math.floor(t)
    local usec = math.floor((t - sec) * 1000000)
    return sec, usec
  end,
  sleep = function(millis)
    luaSocketLib.sleep(millis / 1000)
  end
}
