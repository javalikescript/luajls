local lu = require('luaunit')

local dns = require('jls.net.dns')
local logger = require('jls.lang.logger')

local loop = require('jls.lang.loader').load('loop', 'tests', false, true)

local function assertAddressInfo(host, addr, family)
  local infos = {}
  dns.getAddressInfo(host):next(function(result)
    infos = result
  end)
  if not loop() then
    lu.fail('Timeout reached')
  end
  local found = false
  for _, info in ipairs(infos) do
    if (not family or info.family == family) and info.addr == addr then
      found = true
    end
  end
  if not found then
    logger:logTable(logger.ERROR, infos, 'getAddressInfo('..tostring(host)..')', 5)
  end
  lu.assertTrue(found)
end

function Test_getAddressInfo()
  assertAddressInfo('localhost', '127.0.0.1', 'inet')
end

function Test_getNameInfo()
  local info
  dns.getNameInfo('127.0.0.1'):next(function(result)
    info = result
  end)
  if not loop() then
    lu.fail('Timeout reached')
  end
  --lu.assertEquals(info, 'localhost')
  lu.assertEquals(type(info), 'string')
  --assertAddressInfo(info, '127.0.0.1', 'inet')
end

os.exit(lu.LuaUnit.run())
