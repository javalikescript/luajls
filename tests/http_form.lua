local lu = require('luaunit')

local form = require('jls.net.http.form')
local HttpMessage = require('jls.net.http.HttpMessage')
local HttpRequest = require('jls.net.http.HttpRequest')

function test_create_parse_form()
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

os.exit(lu.LuaUnit.run())
