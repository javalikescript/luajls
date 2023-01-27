local lu = require('luaunit')

local Exception = require('jls.lang.Exception')

function Test_new()
  local function fb(m)
    local e = Exception:new(m)
    return e
  end
  local function fa(m)
    local e = fb(m)
    return e
  end
  local e = fa('msg')
  lu.assertEquals(e:getMessage(), 'msg')
  lu.assertStrContains(e:getStackTrace(), 'fb')
  lu.assertStrContains(e:getStackTrace(), 'fa')
end

function Test_toString()
  local e = Exception:new('msg e')
  local f = Exception:new('msg f', e)
  lu.assertEquals(e:getMessage(), 'msg e')
  lu.assertEquals(f:getMessage(), 'msg f')
  lu.assertStrContains(e:toString(), 'jls.lang.Exception: msg e')
  local s = f:toString()
  lu.assertStrContains(s, 'msg e')
  lu.assertStrContains(s, 'msg f')
end

local function nextCatch(t)
  local nr, ce
  t:next(function(...)
    nr = {n = select('#', ...), ...}
  end):catch(function(e)
    ce = e
  end)
  return nr, ce
end

function Test_try()
  local nr, ce = nextCatch(Exception.try(function(...)
    return ...
  end, 'Hi', 1))
  lu.assertNil(ce)
  lu.assertEquals(nr, {'Hi', 1, n = 2})
  nr, ce = nextCatch(Exception.try(function(...)
    error('Ouch', 0)
  end, 'Hi', 1))
  lu.assertNil(nr)
  lu.assertEquals(ce:getMessage(), 'Ouch')
end

os.exit(lu.LuaUnit.run())
