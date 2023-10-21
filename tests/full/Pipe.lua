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
    return
  end
  local received
  local pipeName = 'pipe.test'
  pipeName = Pipe.normalizePipeName(pipeName)
  local p = Pipe:new()
  function p:onAccept(pb)
    local status, err = pb:readStart(function(err, data)
      logger:fine('pb:read "%s", "%s"', err, data)
      if data then
        pb:write('Hi '..tostring(data))
        received = data
      else
        pb:close()
        p:close()
      end
    end)
    logger:fine('pb:readStart() => %s, %s', status, err)
  end
  p:bind(pipeName):next(function()
    local pc = Pipe:new()
    logger:fine('client connect(%s)', pipeName)
    pc:connect(pipeName):next(function()
      logger:fine('client connected')
      local status, err = pc:readStart(function(err, data)
        logger:fine('pc:read "%s", "%s"', err, data)
        pc:close()
      end)
      logger:fine('pc:readStart() => %s, %s', status, err)
      pc:write('John')
    end):catch(function(err)
      logger:warn('client pipe error %s', err)
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
