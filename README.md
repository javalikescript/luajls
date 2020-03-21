luajls aims to be a standard library for stand-alone [Lua](https://www.lua.org/) applications

The library provides an abstract interface to the underlying operating system, such as file system and network access.
The jls Lua library is composed of a set of jls Lua modules.
The jls Lua library also provides interface for general purpose libraries such as JSON, ZIP, SSL.
The main targeted OSes are Linux and Windows.

It provides:
* language basics such as class definition, module loading, logging, promise, event loop, process
* file system manipulation, input/output, file and networking access, serial communication
* utility modules for date and time, JSON format, deflate, ZIP file, scheduling and WebView

The only required dependency is Lua 5.3.
Optional dependencies are Lua modules such as luafilesystem, luasocket, luv, lua-openssl, lua-cjson.
By example, the file system manipulation requires one of the luafilesystem or the luv dependent module.
All the dependencies are available in the [Lua C libraries repository](https://github.com/javalikescript/luaclibs).

As luajls is composed of Lua modules, you need to adapt the environment variables LUA_PATH and LUA_CPATH to include the luajls home directory.
Additionally you have to adapt the environment variable LD_LIBRARY_PATH to include the luajls home directory when using a Lua C module requiring a shared library such as openssl.

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

