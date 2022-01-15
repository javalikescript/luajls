## What is luajls?

luajls is a set of Lua modules for developing stand-alone [Lua](https://www.lua.org/) applications.

The modules provide general-purpose functions such as class definition and promise, to operating system abstractions such as file system and network access. The modules support asynchronous I/O based on event loops.

The main targeted operating systems are Linux and Windows.

## What are the features?

luajls provides:
* language basics such as class definition, module loading, logging, promise, event loop, threads, processes
* file system manipulation, I/O, file and networking access, serial communication, streams
* HTTP client and server, MQTT, web socket with support for secured communication using SSL
* utility modules for List and Map, date and time, JSON and XML formats, deflate, ZIP and tar files, scheduling, worker and web view

## What does it look like?

The following is the hello world HTTP server script.

```lua
local event = require('jls.lang.event')
local HttpServer = require('jls.net.http.HttpServer')

local hostname, port = '::', 8080
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

## How to install and use it?

Just drop the _jls_ folder in your Lua path.

The only required dependency is Lua 5.4.
Optional dependencies are C-based or plain Lua modules such as luafilesystem, luasocket, luv, lua-openssl, lua-cjson.
By example, the file system manipulation requires one of the luafilesystem or the luv dependent module.

Lua, luajls and all the dependencies are available in the [Lua C libraries repository](https://github.com/javalikescript/luaclibs).

As luajls is composed of Lua modules, you need to adapt the environment variables LUA_PATH and LUA_CPATH to include the luajls home directory.


### LuaRocks

luajls, with Lua 5.3, can be installed with [LuaRocks](https://luarocks.org/), depending on your needs you could pick one of the following module:
* [luajls](https://luarocks.org/modules/javalikescript/luajls) module is only composed of Lua modules.
* [luajls-lfs](https://luarocks.org/modules/javalikescript/luajls-lfs) module adds C module dependencies, mainly luafilesystem and luasocket.
  Prerequisites on Linux
  `sudo apt install luarocks lua5.3 lua5.3-dev libz-dev`
* [luajls-luv](https://luarocks.org/modules/javalikescript/luajls-luv) module adds C module dependencies, mainly libuv and openssl.
  Prerequisites on Linux
  `sudo apt install luarocks lua5.3 lua5.3-dev libz-dev cmake libssl-dev`

The installation on Windows is quite difficult and painful, I recommend you to download the binaries.


## What do you want to do?

Read the [user manual](https://github.com/javalikescript/luajls/blob/master/doc_topics/manual.md) or the [API documentation](http://javalikescript.free.fr/lua/docs/).

Download [binaries](https://github.com/javalikescript/luajls/releases/latest) or access the [source code](https://github.com/javalikescript/luajls).

Go to the [web site](http://javalikescript.free.fr/lua/).
