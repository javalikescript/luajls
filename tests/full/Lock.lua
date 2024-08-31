local lu = require('luaunit')

local Lock = require('jls.lang.Lock')

function Test_lock_unlock()
  local lock = Lock:new()
  lock:lock()
  lock:unlock()
  lock:finalize()
end

os.exit(lu.LuaUnit.run())
