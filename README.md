<div align="center">

•
[Manual](https://github.com/javalikescript/luajls/blob/master/doc_topics/manual.md "User manual")
•
[Docs](https://javalikescript.github.io/luajls/ "API documentation")
•
[Downloads](https://github.com/javalikescript/luajls/releases/latest "Release binaries")
•

</div>


## What is luajls?

luajls is a set of Lua modules for developing stand-alone [Lua](https://www.lua.org/) applications.

The modules provide general-purpose functions such as class definition and promise, to operating system abstractions such as file system and network access.
The modules support asynchronous I/O based on event loops.

<img src="./luajls.svg" alt="luajls stands on the shoulders of giants">

The main targeted operating systems are Linux and Windows.

## What are the features?

luajls provides:
* language basics such as class definition, logging, exception, promise, event loop, threads, processes
* file system manipulation, I/O, file and networking access, serial communication, pipe, streams
* TCP, UDP, HTTP, WebSocket, MQTT client and server with support for secured communication using SSL
* utility modules for list and map, date and time, JSON and XML formats, AST, codec, message digest, deflate, ZIP and tar files, scheduling, worker and web view

## What does it look like?

The following is the hello world HTTP server script.

```lua
local event = require('jls.lang.event')
local HttpServer = require('jls.net.http.HttpServer')

local httpServer = HttpServer:new()
httpServer:bind('::', 8000)
httpServer:createContext('/', function(exchange)
  local response = exchange:getResponse()
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

luajls supports the async/await pattern.

```lua
local event = require('jls.lang.event')
local Promise = require('jls.lang.Promise')
local HttpClient = require('jls.net.http.HttpClient')

local function nodePattern(name)
  local namePattern = string.gsub(name, '%a', function(a) return '['..string.lower(a)..string.upper(a)..']' end)
  return '<%s*'..namePattern..'%s*>%s*([^<]*)%s*<%s*/%s*'..namePattern..'%s*>'
end

Promise.async(function(await)
  local client = HttpClient:new('http://www.lua.org')
  local response = await(client:fetch('/'))
  local body = await(response:text())
  client:close()
  print(string.match(body, nodePattern('title')))
end)

event:loop()
```

## How to install and use it?

Just drop the *jls* folder in your Lua path.

The only required dependency is Lua.
Optional dependencies are C-based or plain Lua modules such as *luafilesystem*, *luasocket*, *luv*, *lua-openssl*, *lua-cjson*.
By example, the file system manipulation requires one of the *luafilesystem* or the *luv* dependent module.
The recommended dependency is *luv* as it will provide you a uniform support of the *io*, *lang* and *net* packages.

Lua, luajls and all the dependencies are available in the [Lua C libraries repository](https://github.com/javalikescript/luaclibs).

As luajls is composed of Lua modules, you need to adapt the environment variables *LUA_PATH* and *LUA_CPATH* to include the luajls home directory.

luajls is available on winget 
```sh
winget install luajls
```

luajls is also available on [LuaRocks](https://luarocks.org/modules/javalikescript/luajls).


## What are the supported Lua versions?

The only fully supported version is the latest, currently Lua 5.4.

In order to support the majority of Lua engines, an effort is made to provide a good level of compatibility for Lua 5.1 and LuaJIT.
Lua 5.1 compatibility is achived by using a transcompiler and is available in the respective 5.1 releases, the default code base is not fully compatible with Lua 5.1.


## What do you want to do?

Browse the [examples](https://github.com/javalikescript/luajls/tree/master/examples)
or applications such as [Fast Cut](https://github.com/javalikescript/fcut) and [Light Home Automation](https://github.com/javalikescript/lha).

Read the [user manual](https://github.com/javalikescript/luajls/blob/master/doc_topics/manual.md) or the [API documentation](https://javalikescript.github.io/luajls/).

Download [binaries](https://github.com/javalikescript/luajls/releases/latest "Windows 64bits, Linux 64bits, WD MyCloud (Gen1, Sequoia), Raspberry Pi (3 Model B+)") or access the [source code](https://github.com/javalikescript/luajls).
