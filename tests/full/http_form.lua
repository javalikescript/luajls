local lu = require('luaunit')

local form = require('jls.net.http.form')
local HttpMessage = require('jls.net.http.HttpMessage')
local HttpRequest = require('jls.net.http.HttpRequest')
local HttpHeaders = require('jls.net.http.HttpHeaders')
local strings = require('jls.util.strings')

function Test_create_parse_form()
  local request = HttpRequest:new()
  local msg1 = HttpMessage:new()
  local msg2 = HttpMessage:new()
  local messages = {msg1, msg2}
  form.setFormDataName(msg1, 'input')
  msg1:setBody('input value')
  form.setFormDataName(msg2, 'pictures', 'PIC0001.JPG', 'application/octet-stream')
  msg2:setBody('FF123456')
  form.createFormRequest(request, messages)
  --print('request:getBody()', request:getBody())
  local parsedMessages = form.parseFormRequest(request)
  lu.assertEquals(#parsedMessages, #messages)
  lu.assertEquals(form.getFormDataName(parsedMessages[1]), 'input')
  lu.assertEquals(parsedMessages[1]:getBody(), 'input value')
end

function Test_HttpHeaders()
  local headers = HttpHeaders:new()
  local lines = {
    'cache-control: public, max-age=3600',
    'content-encoding: gzip',
    "content-security-policy: default-src 'self' 'unsafe-inline' data: https://sample.org; frame-ancestors 'self' sample.org *.sample.org",
    'content-type: text/html; charset=utf-8',
    'date: Sun, 26 Jun 2022 16:40:32 GMT',
    'expires: Sun, 26 Jun 2022 17:40:32 GMT',
    'referrer-policy: strict-origin-when-cross-origin',
    'strict-transport-security: max-age=3600; includeSubDomains',
    'vary: Accept-Encoding',
    'x-content-type-options: nosniff',
    'x-frame-options: SAMEORIGIN',
    'x-xss-protection: 1; mode=block',
  }
  for _, line in ipairs(lines) do
    headers:parseHeaderLine(line)
  end
  local rLines = strings.split(headers:getRawHeaders(), '\r\n')
  lu.assertEquals(rLines, lines)
end

function Test_HttpHeaders_set_cookie()
  local headers = HttpHeaders:new()
  local lines = {
    'cache-control: public, max-age=3600',
    'set-cookie: a=b',
    'set-cookie: b=c',
  }
  for _, line in ipairs(lines) do
    headers:parseHeaderLine(line)
  end
  local rLines = strings.split(headers:getRawHeaders(), '\r\n')
  lu.assertEquals(rLines, lines)
end

function Test_HttpHeaders_values()
  local headers = HttpHeaders:new()
  local lines = {
    'cache-control: public',
    'cache-control: max-age=3600',
  }
  for _, line in ipairs(lines) do
    headers:parseHeaderLine(line)
  end
  local rLines = strings.split(headers:getRawHeaders(), '\r\n')
  lu.assertEquals(rLines, {'cache-control: public, max-age=3600'})
end

os.exit(lu.LuaUnit.run())
