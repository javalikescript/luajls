local lu = require('luaunit')

local Serial = require('jls.io.Serial')
local event = require('jls.lang.event')
local system = require('jls.lang.system')
local StreamHandler = require('jls.io.StreamHandler')
local ProcessBuilder = require('jls.lang.ProcessBuilder')
local Promise = require('jls.lang.Promise')
local File = require('jls.io.File')

local loop = require('jls.lang.loopWithTimeout')

local SOCAT = '/usr/bin/socat'
local TEST_PATH = 'tests/full'
local TEST_SERIAL = TEST_PATH..'/pty0'
local TEST_SERIAL_2 = TEST_PATH..'/pty1'
local SERIAL_OPTS = ',b9600,raw,echo=0'
local SERIAL_PARAMS = {
  baudRate = 9600,
  dataBits = 8,
  stopBits = 1,
  parity = 0
}

-- socat -hh | grep -e PTY -e TERM
-- socat PTY,link=/tmp/ttys0,raw,echo=0 PTY,link=/tmp/ttys1,raw,echo=0

local function wait(millis)
  return Promise:new(function(resolve, reject)
    event:setTimeout(resolve, millis)
  end)
end

function Test_serial_read_write_with_socat()
  if not File:new(SOCAT):exists() then
    print('/!\\ skipping test, socat not found', SOCAT)
    lu.success()
    return
  end
  local received, received2
  local pb = ProcessBuilder:new(SOCAT, 'pty,link='..TEST_SERIAL..SERIAL_OPTS, 'pty,link='..TEST_SERIAL_2..SERIAL_OPTS)
  pb:setRedirectOutput(system.output)
  pb:setRedirectError(system.error)

  -- TODO test getSerial

  local ph, err = pb:start()
  lu.assertNil(err)
  lu.assertNotNil(ph)
  -- redirect error
  Promise.async(function(await)
    await(wait(500))
    if not ph:isAlive() then
      print('socat is not running')
      return
    end
    local serial = Serial:open(TEST_SERIAL, SERIAL_PARAMS)
    local sh = StreamHandler.promises()
    local serial2 = Serial:open(TEST_SERIAL_2, SERIAL_PARAMS)
    local sh2 = StreamHandler.promises()
    --print('start read/write on serial')
    --serial:readStart(StreamHandler.tee(StreamHandler.std, sh))
    serial:readStart(sh)
    serial2:readStart(sh2)
    serial:write('Hi\n')
    serial2:write('Hello\n')
    received = await(sh:read())
    received2 = await(sh2:read())
    ph:destroy()
    await(serial:close())
    await(serial2:close())
  end):catch(function(r)
    print('error', r)
  end)
  if not loop() then
    ph:destroy()
    print(string.format('received "%s", "%s"', received, received2))
    lu.fail('Timeout reached')
  end
  lu.assertEquals(received, 'Hello\n')
  lu.assertEquals(received2, 'Hi\n')
end

os.exit(lu.LuaUnit.run())
