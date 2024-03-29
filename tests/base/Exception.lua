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

function Test_pcall()
  local status, e
  status, e = Exception.pcall(function()
    return 'ok'
  end)
  lu.assertTrue(status)
  lu.assertEquals(e, 'ok')
  status, e = Exception.pcall(function()
    error('ouch')
  end)
  lu.assertFalse(status)
  --print(e)
  lu.assertEquals(e:getMessage(), 'ouch')
end

os.exit(lu.LuaUnit.run())
