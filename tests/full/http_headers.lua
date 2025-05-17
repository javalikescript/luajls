local lu = require('luaunit')

local HttpHeaders = require('jls.net.http.HttpHeaders')
local HttpMessage = require('jls.net.http.HttpMessage')

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
  lu.assertEquals(HttpMessage.parseHeaderValue('text/html'), 'text/html')
  lu.assertEquals(HttpMessage.parseHeaderValue('text/html;level=2;q=0.4'), 'text/html')
  lu.assertEquals({HttpMessage.parseHeaderValue('text/html;level=2;q=0.4')}, {'text/html', {'level=2', 'q=0.4'}})
end

function Test_setCookie()
  local name, value = 'aname', 'avalue'
  local name2, value2 = 'aname2', 'avalue2'
  local headers = HttpHeaders:new()
  headers:setCookie(name, value)
  headers:setCookie(name2, value2)
  lu.assertEquals(headers:getHeader('set-cookie'), {'aname=avalue', 'aname2=avalue2'})

  headers:setHeader('cookie', 'aname=avalue; aname2=avalue2')
  lu.assertEquals(headers:getCookie(name), value)
  lu.assertEquals(headers:getCookie(name2), value2)
end

os.exit(lu.LuaUnit.run())
