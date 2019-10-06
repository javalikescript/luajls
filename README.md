luajls is a standard library for [Lua](https://www.lua.org/)

The library provides an abstract interface to the underlying operating system, such as file system and network.
The jls Lua library includes a set of Lua modules providing an API to abstract the host platform.
The main targeted OSes are Linux and Windows.

It provides:
* language basics such as class definition, module loading, logging, promises
* file system manipulation, input/output, file and networking access, serial communication
* utility modules for date and time, JSON format, structs, deflate, zip file and WebView

The only required dependency is Lua 5.3.
Other dependencies are Lua native modules such as lfs, luasocket, luv, lua-openssl, lua-cjson.
All the dependencies are available in the [Lua C libraries repository](https://github.com/javalikescript/luaclibs).

```lua
local event = require('jls.lang.event')
local HttpServer = require('jls.net.http.HttpServer')

local hostname, port = '::', 3001
local httpServer = HttpServer:new()
httpServer:bind(hostname, port):next(function()
  print('Server bound to "'..hostname..'" on port '..tostring(port))
end)
httpServer:createContext('/', function(httpExchange)
  local response = httpExchange:getResponse()
  response:setBody([[<!DOCTYPE html>
  <html>
    <body>
      <p>It works !</p>
    </body>
  </html>
  ]])
end)
event:loop()
```

See the [web site](http://javalikescript.free.fr/lua/) and the [API documentation](http://javalikescript.free.fr/lua/docs/).

Download [binary](http://javalikescript.free.fr/lua/download/) or access the [source code](https://github.com/javalikescript/luajls).

