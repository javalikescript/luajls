local lu = require('luaunit')

local loader = require('jls.lang.loader')
local event = require('jls.lang.event')
local loop = require('jls.lang.loopWithTimeout')
local logger = require('jls.lang.logger')
local Pipe = loader.tryRequire('jls.io.Pipe')

function Test_default()
  if event ~= loader.getRequired('jls.lang.event-luv') then
    print('/!\\ skipping default test')
    lu.success()
  end
  local received
  local pipeName = 'pipe.test'
  pipeName = Pipe.normalizePipeName(pipeName)
  local p = Pipe:new()
  function p:onAccept(pb)
    local status, err = pb:readStart(function(err, data)
      logger:fine('pb:read "'..tostring(err)..'", "'..tostring(data)..'"')
      if data then
        pb:write('Hi '..tostring(data))
        received = data
      else
        pb:close()
        p:close()
      end
    end)
    logger:fine('pb:readStart() => '..tostring(status)..', '..tostring(err))
  end
  p:bind(pipeName):next(function()
    local pc = Pipe:new()
    logger:fine('client connect('..tostring(pipeName)..')')
    pc:connect(pipeName):next(function()
      logger:fine('client connected')
      local status, err = pc:readStart(function(err, data)
        logger:fine('pc:read "'..tostring(err)..'", "'..tostring(data)..'"')
        pc:close()
      end)
      logger:fine('pc:readStart() => '..tostring(status)..', '..tostring(err))
      pc:write('John')
    end):catch(function(err)
      logger:warn('client pipe error '..tostring(err))
      pc:close()
    end)
  end)
  logger:fine('looping')
  if not loop(function()
    p:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(received, 'John')
end

os.exit(lu.LuaUnit.run())
