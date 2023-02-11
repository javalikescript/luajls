local lu = require('luaunit')

local strings = require("jls.util.strings")

function Test_equalsIgnoreCase()
  lu.assertTrue(strings.equalsIgnoreCase(nil, nil))
  lu.assertTrue(strings.equalsIgnoreCase('', ''))
  lu.assertTrue(strings.equalsIgnoreCase('a', 'a'))
  lu.assertTrue(strings.equalsIgnoreCase('a', 'A'))
  lu.assertFalse(strings.equalsIgnoreCase('', nil))
  lu.assertFalse(strings.equalsIgnoreCase('a', 'b'))
  lu.assertFalse(strings.equalsIgnoreCase(1, 1))
end

function Test_split()
  lu.assertEquals(strings.split('', ','), {})
  lu.assertEquals(strings.split('a', ','), {'a'})
  lu.assertEquals(strings.split('a,b,c', ','), {'a', 'b', 'c'})
end

function Test_cuts()
  lu.assertEquals(strings.cuts('abcdefghijklmnopqrstuvwxyz', 2, 2, 3), {'ab', 'cd', 'efg'})
  lu.assertEquals(strings.cuts('abcdefghijklmnopqrstuvwxyz', 2, 2, 99), {'ab', 'cd', 'efghijklmnopqrstuvwxyz'})
  lu.assertEquals(strings.cuts('abc', 2, 2, 3), {'ab', 'c', ''})
end

function Test_hash()
  lu.assertEquals(strings.hash(''), 0)
  lu.assertEquals(strings.hash('\0\0'), 0)
  lu.assertEquals(strings.hash('\1'), 1)
  lu.assertEquals(strings.hash('\1\1'), 32)
  lu.assertEquals(strings.hash('Hi'), 2337)
  lu.assertEquals(strings.hash('Hello'), 69609650)
  if _VERSION >= 'Lua 5.3' then
    lu.assertEquals(strings.hash('A long long long sentence'), -1198834433238344152)
  end
end

function Test_padLeft()
  lu.assertEquals(strings.padLeft('Hello', 2), 'lo')
  lu.assertEquals(strings.padLeft('Hi', 6), '    Hi')
  lu.assertEquals(strings.padLeft('Hi', 6, '-'), '----Hi')
end

function Test_formatInteger()
  lu.assertEquals(strings.formatInteger(0), '0')
  lu.assertEquals(strings.formatInteger(-9), '-9')
  lu.assertEquals(strings.formatInteger(9), '9')
  lu.assertEquals(strings.formatInteger(10), '10')
  lu.assertEquals(strings.formatInteger(10, 10), '10')
  lu.assertEquals(strings.formatInteger(9, 16), '9')
  lu.assertEquals(strings.formatInteger(10, 16), 'A')
  lu.assertEquals(strings.formatInteger(69609650, 10), '69609650')
  lu.assertEquals(strings.formatInteger(69609650, 16), '42628B2')
  lu.assertEquals(strings.formatInteger(69609650, 64), '49YYn')
  lu.assertEquals(strings.formatInteger(10, 16, 4), '000A')
  lu.assertEquals(strings.formatInteger(-10, 16, 4), '-00A')
end

function Test_variableByteInteger()
  for _, i in ipairs({0, 1, 250, 30000}) do
    lu.assertEquals(strings.decodeVariableByteInteger(strings.encodeVariableByteInteger(i)), i)
  end
end

os.exit(lu.LuaUnit.run())
