local lu = require('luaunit')

local logger = require('jls.lang.logger')
local SerialWorker = require('jls.util.SerialWorker')
local loop = require('jls.lang.loopWithTimeout')

function Test_default()
  local responses = {}
  local sw = SerialWorker:new()
  sw:call(function(d)
    return 'Hi '..tostring(d)
  end, 'John'):next(function(d)
    table.insert(responses, d or '')
  end)
  sw:call(function(d)
    return 'Hello '..tostring(d)
  end, 'Mary'):next(function(d)
    table.insert(responses, d or '')
  end):finally(function()
    sw:close()
  end)
  logger:info('looping')
  if not loop(function()
    sw:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(responses, {'Hi John', 'Hello Mary'})
end

function Test_reject()
  local rejects = {}
  local sw = SerialWorker:new()
  sw:call(function(d)
    return nil, 'Sorry '..tostring(d)
  end, 'John'):catch(function(d)
    table.insert(rejects, d or '')
  end)
  sw:call(function(d)
    error('Ouch '..tostring(d))
  end, 'Mary'):catch(function(d)
    table.insert(rejects, d or '')
  end):finally(function()
    sw:close()
  end)
  logger:info('looping')
  if not loop(function()
    sw:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(#rejects, 2)
  lu.assertEquals(rejects[1], 'Sorry John')
  lu.assertNotNil(string.match(rejects[2], 'Ouch Mary'))
end

os.exit(lu.LuaUnit.run())
