local lu = require('luaunit')

local HttpHeaders = require('jls.net.http.HttpHeaders')
local HttpMessage = require('jls.net.http.HttpMessage')
local Attributes = require('jls.net.http.Attributes')

--[[
  Accept: text/*;q=0.3, text/html;q=0.7, text/html;level=1, text/html;level=2;q=0.4, */*;q=0.5
  Accept-Encoding: gzip, deflate, br
  Accept-Language: en-US,en;q=0.9,fr;q=0.8
  cache-control: no-store, no-cache, must-revalidate
  content-type: text/html; charset=UTF-8
  Keep-Alive: timeout=15, max=94
]]
function Test_getHeaderValues()
  local message = HttpMessage:new()
  message:setHeader('Accept', 'text/*;q=0.3, text/html;q=0.7, text/html;level=1, text/html;level=2;q=0.4, */*;q=0.5')
  message:setHeader('Accept-Language', 'en-US,en;q=0.9,fr;q=0.8')
  lu.assertEquals(message:getHeader('accept-language'), 'en-US,en;q=0.9,fr;q=0.8')
  lu.assertEquals(message:getHeaderValues('Accept-Language'), {'en-US', 'en;q=0.9', 'fr;q=0.8'})
end

function Test_hasHeaderValue()
  local message = HttpMessage:new()
  message:setHeader('Accept-Language', 'en-US,en;q=0.9,fr;q=0.8')
  message:setHeader('Content-Type', 'application/json; charset=utf-8')
  lu.assertEquals(message:hasHeaderValue('accept-language', 'en'), true)
  lu.assertEquals(message:hasHeaderValue('accept-language', 'en-US'), true)
  lu.assertEquals(message:hasHeaderValue('accept-language', 'fr'), true)
  lu.assertEquals(message:hasHeaderValue('accept-language', 'en-GB'), false)
  lu.assertEquals(message:hasHeaderValue('content-type', 'application/JSON'), false)
  lu.assertEquals(message:hasHeaderValue('content-type', 'application/JSON', true), true)
  lu.assertEquals(message:hasHeaderValueIgnoreCase('content-type', 'application/JSON'), true)
end

function Test_parseHeaderValue()
  lu.assertNil(HttpMessage.parseHeaderValue(nil))
  lu.assertEquals(HttpMessage.parseHeaderValue('text/html'), 'text/html')
  lu.assertEquals(HttpMessage.parseHeaderValue('text/html;level=2;q=0.4'), 'text/html')
  lu.assertEquals({HttpMessage.parseHeaderValue('text/html;level=2;q=0.4')}, {'text/html', {'level=2', 'q=0.4'}})
end

function Test_setHeader_and_getHeader()
  local h = HttpHeaders:new()
  h:setHeader('Content-Type', 'text/plain')
  lu.assertEquals(h:getHeader('content-type'), 'text/plain')
  h:setHeader('X-Number', 42)
  lu.assertEquals(h:getHeader('x-number'), '42')
  h:setHeader('X-Boolean', true)
  lu.assertEquals(h:getHeader('x-boolean'), 'true')
  h:setHeader('X-Nil', nil)
  lu.assertNil(h:getHeader('x-nil'))
end

function Test_setHeader_table()
  local h = HttpHeaders:new()
  h:setHeader('X-List', {'a', 'b', 1, 'c'})
  lu.assertEquals(h:getHeader('x-list'), {'a', 'b', 'c'})
  h:setHeader('X-Empty', {})
  lu.assertNil(h:getHeader('x-empty'))
  h:setHeader('X-Ignored', function() end)
  lu.assertNil(h:getHeader('x-ignored'))
end

function Test_getHeaderValues()
  local h = HttpHeaders:new()
  lu.assertEquals(h:getHeaderValues('missing'), {})
  h:setHeader('Accept', 'text/html, application/json')
  lu.assertEquals(h:getHeaderValues('accept'), {'text/html', 'application/json'})
  h:setHeader('X-Single', 'value')
  lu.assertEquals(h:getHeaderValues('x-single'), {'value'})
  h:getHeadersTable()['x-raw'] = 42
  lu.assertEquals(h:getHeaderValues('x-raw'), {42})
  lu.assertEquals({h:getHeaderValue('x-raw')}, {42})
end

function Test_setHeaderValues()
  local h = HttpHeaders:new()
  h:setHeaderValues('Accept', {'text/html', 'application/json'})
  lu.assertEquals(h:getHeader('accept'), 'text/html, application/json')
  h:setHeaderValues('X-Empty', {})
  lu.assertNil(h:getHeader('x-empty'))
  h:setHeaderValues('X-NoTable', 'ignored')
  lu.assertNil(h:getHeader('x-notable'))
end

function Test_hasHeaderValue()
  local h = HttpHeaders:new()
  h:setHeader('Content-Type', 'text/html; charset=utf-8')
  lu.assertTrue(h:hasHeaderValue('content-type', 'text/html'))
  lu.assertFalse(h:hasHeaderValue('content-type', 'text/plain'))
  local found, params = h:hasHeaderValue('content-type', 'text/html')
  lu.assertEquals(params, {'charset=utf-8'})
  h:setHeader('X-Token', 'ABC')
  lu.assertTrue(h:hasHeaderValueIgnoreCase('x-token', 'abc'))
  lu.assertFalse(h:hasHeaderValue('x-token', 'abc'))
end

function Test_cookies()
  local h = HttpHeaders:new()
  h:setHeader('Cookie', 'a=1; b=2')
  lu.assertEquals(h:getCookies(), {a = '1', b = '2'})
  lu.assertEquals(h:getCookie('a'), '1')
  lu.assertNil(h:getCookie('missing'))
  h:setHeader('Cookie', 'x=1; x=2')
  lu.assertEquals({h:getCookie('x')}, {'1', '2'})
end

function Test_setCookie()
  local h = HttpHeaders:new()
  h:setCookie('session', 'abc', {'Path=/', 'HttpOnly'})
  lu.assertEquals(h:getHeader('set-cookie'), {'session=abc; Path=/; HttpOnly'})
  h:setCookie('session', 'def')
  lu.assertEquals(h:getHeader('set-cookie'), {'session=def'})
  h:setCookie('other', 'xyz')
  lu.assertEquals(h:getHeader('set-cookie'), {'session=def', 'other=xyz'})
end

function Test_addHeaderValue()
  local h = HttpHeaders:new()
  h:addHeaderValue('Accept', 'text/html')
  lu.assertEquals(h:getHeader('accept'), 'text/html')
  h:addHeaderValue('Accept', 'application/json')
  lu.assertEquals(h:getHeader('accept'), 'text/html, application/json')
  h:addHeaderValue('Cookie', 'a=1')
  h:addHeaderValue('Cookie', 'b=2')
  lu.assertEquals(h:getHeader('cookie'), 'a=1; b=2')
  h:addHeaderValue('Set-Cookie', 'a=1')
  h:addHeaderValue('Set-Cookie', 'b=2')
  lu.assertEquals(h:getHeader('set-cookie'), {'a=1', 'b=2'})
  h:addHeaderValue('Set-Cookie', 'c=3')
  lu.assertEquals(h:getHeader('set-cookie'), {'a=1', 'b=2', 'c=3'})
end

function Test_parseHeaderLine()
  local h = HttpHeaders:new()
  lu.assertTrue(h:parseHeaderLine('Content-Type: text/html'))
  lu.assertEquals(h:getHeader('content-type'), 'text/html')
  lu.assertFalse(h:parseHeaderLine('invalid line'))
  h:parseHeaderLine('X-Spaced:   value')
  lu.assertEquals(h:getHeader('x-spaced'), 'value')
end

function Test_headersTable()
  local h = HttpHeaders:new({a = 'A', b = {'B1', 'B2'}})
  lu.assertEquals(h:getHeader('a'), 'A')
  lu.assertEquals(h:getHeader('b'), {'B1', 'B2'})
  local h2 = HttpHeaders:new(h)
  lu.assertEquals(h2:getHeader('a'), 'A')
  h2:setHeadersTable({c = 'C'})
  lu.assertEquals(h2:getHeader('a'), nil)
  lu.assertEquals(h2:getHeader('c'), 'C')
  lu.assertFalse(pcall(function()
    h2:addHeadersTable('not a table')
  end))
end

function Test_getRawHeaders()
  local h = HttpHeaders:new()
  h:setHeader('X-One', '1')
  lu.assertEquals(h:getRawHeaders(), 'x-one: 1\r\n')
  h:setHeader('X-Multi', {'a', 'b'})
  lu.assertStrContains(h:getRawHeaders(), 'x-multi: a\r\n')
  lu.assertStrContains(h:getRawHeaders(), 'x-multi: b\r\n')
end

function Test_parseHeaderValue()
  lu.assertEquals({HttpHeaders.parseHeaderValue('text/html')}, {'text/html'})
  local startValue, params = HttpHeaders.parseHeaderValue('text/html; charset=utf-8; q=0.5')
  lu.assertEquals(startValue, 'text/html')
  lu.assertEquals(params, {'charset=utf-8', 'q=0.5'})
  lu.assertNil(HttpHeaders.parseHeaderValue(1))
end

function Test_parseHeaderValueAsTable()
  local startValue, params = HttpHeaders.parseHeaderValueAsTable('text/html; charset=utf-8')
  lu.assertEquals(startValue, 'text/html')
  lu.assertEquals(params, {charset = 'utf-8'})
  local startValue2, params2 = HttpHeaders.parseHeaderValueAsTable('text/html')
  lu.assertEquals(startValue2, 'text/html')
  lu.assertEquals(params2, {})
end

function Test_attributes()
  local a = Attributes:new()
  lu.assertEquals(a:getAttributes(), {})
  lu.assertIs(a:setAttribute('x', 1), a)
  lu.assertEquals(a:getAttribute('x'), 1)
  lu.assertIsNil(a:getAttribute('y'))
  a:setAttribute('y', 'two')
  lu.assertIs(a:removeAttribute('x'), a)
  lu.assertIsNil(a:getAttribute('x'))
  lu.assertIsNil(a:getAttribute('missing'))
  lu.assertEquals(a:getAttributes(), {y = 'two'})
  lu.assertIs(a:setAttributes({a = 1, b = 2}), a)
  lu.assertEquals(a:getAttribute('a'), 1)
  lu.assertEquals(a:getAttribute('b'), 2)
  a:cleanAttributes()
  lu.assertEquals(a:getAttributes(), {})
end

function Test_attributes_instance()
  local exchange = require('jls.net.http.HttpExchange'):new()
  lu.assertIs(exchange:setAttribute('name', 'value'), exchange)
  lu.assertEquals(exchange:getAttribute('name'), 'value')
end

os.exit(lu.LuaUnit.run())
