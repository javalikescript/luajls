local event = require('jls.lang.event')
local File = require('jls.io.File')
local WebView = require('jls.util.WebView')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local ZipFileHttpHandler = require('jls.net.http.handler.ZipFileHttpHandler')

local function contentHandler(body)
  return function(exchange)
    exchange:getResponse():setBody(body)
  end
end

local contentHeader = [[<!DOCTYPE html>
<html><head lang="en">
<meta http-equiv="content-type" content="text/html; charset=UTF-8">
<meta charset="UTF-8">
<style type="text/css">
html {
  height: 100%;
}
body {
  height: 100%;
  margin: 0;
  display: block;
  overflow: hidden;
}
body > div {
  height: 1.5rem;
  text-align: center;
}
body > iframe {
  width: 100%;
  height: calc(100% - 1.5rem);
  border: 0;
}
</style></head>
]]

local frames = {
  {name = 'luajls', href = 'docs/index.html', path = ''},
  {name = 'Lua', href = 'docs/lua/contents.html', path = ''},
  {name = 'LDoc', href = 'docs/ldoc.html', path = ''},
  {name = 'LuaUnit', href = 'docs/luaunit.html', path = ''},
  {name = 'LuaCov', href = 'docs/luacov/index.html', path = ''},
}

local contentBody = '<body><div>'
for i, frame in ipairs(frames) do
  if i > 1 then
    contentBody = contentBody..' - '
  end
  contentBody = contentBody..'<a href="'..frame.href..'" target="iframe">'..frame.name..'</a>'
end
contentBody = contentBody..'</div><iframe name="iframe" src="docs/index.html"></iframe></body>'

local scriptFile = File:new(arg[0]):getAbsoluteFile()
local scriptDir = scriptFile:getParentFile()
local devDir = File:new('../luaclibs')

WebView.open('http://localhost:0/index.html', {
  title = 'Lua JLS Documentation',
  width = 1024,
  height = 768,
  resizable = true,
  contexts = {
    ['/index.html'] = contentHandler(contentHeader..contentBody..'</html>')
  }
}):next(function(webview)
  local httpServer = webview:getHttpServer()
  print('WebView opened with HTTP Server bound on port '..tostring(select(2, httpServer:getAddress())))
  if devDir:isDirectory() then
    httpServer:createContext('/docs/(.*)', FileHttpHandler:new('./doc'))
    httpServer:createContext('/docs/lua/(.*)', FileHttpHandler:new(File:new(devDir, 'lua/doc')))
    httpServer:createContext('/docs/luacov/(.*)', FileHttpHandler:new(File:new(devDir, 'luacov/docs')))
  else
    httpServer:createContext('/docs/(.*)', ZipFileHttpHandler:new(File:new(scriptDir, '../docs.zip')))
  end
  return webview:getThread():ended()
end):catch(function(reason)
  print('Cannot open webview due to '..tostring(reason))
end)

--print('Looping')
event:loop()
event:close()
