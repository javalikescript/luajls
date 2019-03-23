luajls is a standard library for lua

The library provides an abstract interface to the underlying operating system, such as file system and network.
The jls lua library includes a set of lua modules providing an API to abstract the host platform.
The main targeted OSes are Linux and Windows.

It provides:
* language basics such as class definition, module loading, logging, promises
* file system manipulation, input/output, file and networking access, serial communication
* utility modules, for date and time, json format, deflate and zip file, structs and other codecs

The only required dependency is lua 5.3
Other dependencies are lua native modules such as lfs, luasocket, luv, lua-openssl, lua-cjson

```lua
local http = require('jls.net.http')
local event = require('jls.lang.event')

local hostname, port = '::', 3001
local httpServer = http.Server:new()
httpServer:bind(hostname, port):next(function()
  print('Server bound to "'..hostname..'" on port '..tostring(port))
end, function(err)
  print('Cannot bind HTTP server, '..tostring(err))
end)
httpServer:createContext('/', function(httpExchange)
  local response = httpExchange:getResponse()
  response:setStatusCode(http.CONST.HTTP_OK)
  response:setReasonPhrase('OK')
  response:setBody([[<!DOCTYPE html>
  <html>
    <body>
      <p>It works !</p>
    </body>
  </html>
  ]])
end
)
event:loop()
event:close()
```
