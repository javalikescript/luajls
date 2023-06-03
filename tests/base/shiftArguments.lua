local lu = require('luaunit')

local shiftArguments = require('jls.lang.shiftArguments')

function Test_lua()
  lu.assertEquals(shiftArguments({'lua'}), {[-1]='lua'})
  lu.assertEquals(shiftArguments({'lua', 'script.lua'}), {[-1]='lua', [0]='script.lua'})
  lu.assertEquals(shiftArguments({'lua', 'script.lua', '-h'}), {[-1]='lua', [0]='script.lua', '-h'})
  lu.assertEquals(shiftArguments({'lua', '-e', 'print("Hi")'}), {[-3]='lua', [-2]='-e', [-1]='print("Hi")'})
  lu.assertEquals(shiftArguments({'lua', '-'}), {[-2]='lua', [-1]='-'})
  lu.assertEquals(shiftArguments({'lua', '--', 'script.lua'}), {[-2]='lua', [-1]='--', [0]='script.lua'})
end

function Test_bad()
  lu.assertEquals(shiftArguments({}), {})
  lu.assertEquals(shiftArguments(), {})
end

function Test_luvit()
  lu.assertEquals(shiftArguments({[0]='luvit'}, 1), {[-1]='luvit'})
  lu.assertEquals(shiftArguments({[0]='luvit', 'script.lua'}, 1), {[-1]='luvit', [0]='script.lua'})
  lu.assertEquals(shiftArguments({[0]='luvit', '-l', 'mod', 'script.lua'}, 1), {[-3]='luvit', [-2]='-l', [-1]='mod', [0]='script.lua'})
end

os.exit(lu.LuaUnit.run())
