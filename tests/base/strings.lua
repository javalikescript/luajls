local lu = require('luaunit')

local strings = require('jls.util.strings')

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

function Test_cut_deprecated()
  lu.assertEquals(strings.cut(10, 'abcdefghijklmnopqrstuvwxyz'), {'abcdefghij', 'klmnopqrst', 'uvwxyz'})
  lu.assertEquals(strings.cut(13, 'abcdefghijklmnopqrstuvwxyz'), {'abcdefghijklm', 'nopqrstuvwxyz'})
  lu.assertEquals(strings.cut(13, 'abc'), {'abc'})
end

function Test_cut()
  lu.assertEquals({strings.cut('abc=efg=hij', '=')}, {'abc', 'efg=hij'})
  lu.assertEquals({strings.cut('abc===efg=hij', '=+')}, {'abc', 'efg=hij'})
  lu.assertEquals({strings.cut('abc', '=')}, {'abc'})
end

local function forAsList(...)
  local l = {}
  for s in ... do
    table.insert(l, s)
  end
  return l
end

function Test_parts()
  lu.assertEquals(forAsList(strings.parts('abcdefghijklmnopqrstuvwxyz', 10)), {'abcdefghij', 'klmnopqrst', 'uvwxyz'})
  lu.assertEquals(forAsList(strings.parts('abcdefghijklmnopqrstuvwxyz', 13)), {'abcdefghijklm', 'nopqrstuvwxyz'})
  lu.assertEquals(forAsList(strings.parts('abc', 13)), {'abc'})
  lu.assertEquals(forAsList(strings.parts('', ',')), {})
  lu.assertEquals(forAsList(strings.parts('a', ',')), {'a'})
  lu.assertEquals(forAsList(strings.parts('a,b,c', ',')), {'a', 'b', 'c'})
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

function Test_capitalize()
  lu.assertNil(strings.capitalize(nil))
  lu.assertEquals(strings.capitalize(''), '')
  lu.assertEquals(strings.capitalize('hi'), 'Hi')
  lu.assertEquals(strings.capitalize('Hi'), 'Hi')
  lu.assertEquals(strings.capitalize('HI'), 'HI')
end

function Test_escape()
  lu.assertNil(strings.escape(nil))
  lu.assertEquals(strings.escape('aA1, '), 'aA1, ')
  lu.assertEquals(strings.escape('^$()%.[]*+-?'), '%^%$%(%)%%%.%[%]%*%+%-%?')
end

function Test_startsWith()
  lu.assertIsTrue(strings.startsWith('abc', 'a'))
  lu.assertIsTrue(strings.startsWith('abc', 'ab'))
  lu.assertIsTrue(strings.startsWith('abc', ''))
  lu.assertIsFalse(strings.startsWith('abc', 'b'))
end

function Test_endsWith()
  lu.assertIsTrue(strings.endsWith('abc', 'c'))
  lu.assertIsTrue(strings.endsWith('abc', 'bc'))
  lu.assertIsTrue(strings.endsWith('abc', ''))
  lu.assertIsFalse(strings.endsWith('abc', 'a'))
end

function Test_strip()
  lu.assertNil(strings.strip(nil))
  lu.assertEquals(strings.strip(''), '')
  lu.assertEquals(strings.strip(' '), '')
  lu.assertEquals(strings.strip('\n'), '')
  lu.assertEquals(strings.strip('Hi'), 'Hi')
  lu.assertEquals(strings.strip(' Hi'), 'Hi')
  lu.assertEquals(strings.strip('Hi '), 'Hi')
  lu.assertEquals(strings.strip(' Hi '), 'Hi')
  lu.assertEquals(strings.strip('  Hello world !   '), 'Hello world !')
end

os.exit(lu.LuaUnit.run())
