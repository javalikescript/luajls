return function(fn, ...)
  local system = require('jls.lang.system')
  collectgarbage('collect')
  collectgarbage('stop')
  local gcCountBefore = collectgarbage('count')
  local startClock = os.clock()
  local startMillis = system.currentTimeMillis()
  fn(...)
  local endMillis = system.currentTimeMillis()
  local endClock = os.clock()
  local gcCountAfter = collectgarbage('count')
  collectgarbage('restart')
  return endMillis - startMillis, math.floor((endClock - startClock) * 1000), math.floor((gcCountAfter - gcCountBefore) * 1024)
end