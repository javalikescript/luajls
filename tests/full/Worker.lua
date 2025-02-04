local lu = require('luaunit')

local logger = require('jls.lang.logger')
local Worker = require('jls.util.Worker')
local loop = require('jls.lang.loopWithTimeout')

local function assertPostReceive(withData, options)
  local received = nil
  options = options or {}
  local f
  if options.disableReceive then
    f = function(w, d)
      local logr = require('jls.lang.logger')
      local sys = require('jls.lang.system')
      local suffix = d and tostring(d) or '-'
      local message = 'Hi '..suffix
      if w:isConnected() then
        logr:info('worker is connected')
        w:postMessage(message)
        logr:info('posted in worker "%s"', message)
        sys.sleep(100)
      else
        logr:info('not connected')
      end
      logr:info('ending worker')
    end
  else
    f = function(w, d)
      local logr = require('jls.lang.logger')
      local suffix = d and (', '..tostring(d)) or ''
      function w:onMessage(message)
        logr:info('received in worker "%s"', message)
        local reply = 'Hi '..tostring(message)..suffix
        w:postMessage(reply)
        logr:info('posted in worker "%s"', reply)
      end
    end
  end
  logger:info('initializing worker withData: %s, options: %t', withData, options)
  local w = Worker:new(f, withData and 'cheers' or nil, function(self, message)
    logger:info('received from worker "%s"', message)
    received = message
    self:close()
  end, options)
  if not options.disableReceive then
    logger:info('posting to worker')
    w:postMessage('John')
  end
  logger:info('looping')
  if not loop(function()
    w:close()
  end) then
    lu.fail('Timeout reached')
  end
  if options.disableReceive then
    lu.assertEquals(received, withData and 'Hi cheers' or 'Hi -')
  else
    lu.assertEquals(received, withData and 'Hi John, cheers' or 'Hi John')
  end
end

function Test_default()
  assertPostReceive()
end

function Test_default_with_data()
  assertPostReceive(true)
end

function Test_TCP()
  assertPostReceive(false, {scheme = 'tcp'})
end

function Test_disable_receive()
  assertPostReceive(false, {disableReceive = true})
end

function Test_disable_receive_with_data()
  assertPostReceive(true, {disableReceive = true})
end

function Test_ring()
  assertPostReceive(false, {disableReceive = true, ringSize = 4096})
end

function Test_ring_with_data()
  assertPostReceive(true, {disableReceive = true, ringSize = 4096})
end

local function assertMultiplePostReceive(options)
  local count = 0
  options = options or {}
  logger:info('initializing worker options: %t', options)
  local w = Worker:new(function(w, d)
    local logr = require('jls.lang.logger')
    local sys = require('jls.lang.system')
    for i = 1, 100 do
      if w:isConnected() then
        w:postMessage('message '..i..' -----------')
      else
        break
      end
    end
    w:postMessage('close')
    sys.sleep(100)
    logr:info('ending worker')
  end, nil, function(self, message)
    logger:info('received from worker "%s"', message)
    if message == 'close' then
      self:close()
    else
      count = count + 1
    end
  end, options)
  logger:info('looping')
  if not loop(function()
    w:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(count, 100)
end

function Test_multi()
  assertMultiplePostReceive()
end

function Test_multi_tcp()
  assertMultiplePostReceive({scheme = 'tcp'})
end

function Test_multi_disable_receive()
  assertMultiplePostReceive({disableReceive = true})
end

function Test_multi_ring()
  assertMultiplePostReceive({disableReceive = true, ringSize = 1024})
end

os.exit(lu.LuaUnit.run())
