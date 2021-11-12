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

local content = [[<!DOCTYPE html>
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
</style></head><body>
  <div>
    <a href="docs/topics/intro.md.html" target="iframe">Luajls documentation</a>,
    <a href="docs/index.html" target="iframe">index</a>-
    <a href="docs/lua/contents.html" target="iframe">Lua reference</a>
  </div>
  <iframe name="iframe" src="welcome.html"></iframe>
</body></html>
]]

local welcome = [[<!DOCTYPE html>
<html><body>
  <h2>Welcome !</h2>
</body></html>
]]

local scriptFile = File:new(arg[0]):getAbsoluteFile()
local scriptDir = scriptFile:getParentFile()
local devDir = File:new('../luaclibs')

WebView.open('http://localhost:0/index.html', {
  title = 'Luajls Doc',
  width = 800,
  height = 600,
  resizable = true,
  contexts = {
    ['/index.html'] = contentHandler(content),
    ['/welcome.html'] = contentHandler(welcome)
  }
}):next(function(webview)
  local httpServer = webview:getHttpServer()
  print('WebView opened with HTTP Server bound on port '..tostring(select(2, httpServer:getAddress())))
  if devDir:isDirectory() then
    httpServer:createContext('/docs/(.*)', FileHttpHandler:new('./doc'))
    httpServer:createContext('/docs/lua/(.*)', FileHttpHandler:new(File:new(devDir, 'lua/doc')))
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
