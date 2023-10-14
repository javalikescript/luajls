# Introduction

## Audience

This document is intended for Lua users wanting to use and understand the luajls library, more broadly to people developping standalone Lua application.
It is presumed that the reader has a good knowledge of Lua, please consult the Lua [reference manual](https://www.lua.org/manual/5.4/manual.html) and [Programming in Lua](https://www.lua.org/pil/) to learn details regarding Lua itself.


## Overview

luajls is a set of Lua modules for developing stand-alone [Lua](https://www.lua.org/) applications.

The modules provide general-purpose functions such as class definition and promise, to operating system abstractions such as file system and network access.
The modules support asynchronous I/O based on an event loop.

The modules expose an API to abstract the host platform and general purpose libraries such as _SSL_, _JSON_, _XML_, _ZIP_.
The main targeted OSes are _Linux_ and _Windows_.

The only required dependency is Lua 5.4

Optional dependencies are C and Lua modules such as _luafilesystem_, _luasocket_, _luv_, _lua-openssl_, _lua-cjson_.
By example, the file system manipulation requires one of the _luafilesystem_ or the _luv_ dependent module.

The recommended dependency is *luv* as it will provide you a uniform support of the *io*, *lang* and *net* packages.

See [Lua JLS repository](https://github.com/javalikescript/luajls)
and the [Lua C libraries repository](https://github.com/javalikescript/luaclibs)


## General Considerations

### Motivations and Reasoning

The motivation is to facilitate the development of complex standalone applications.

Building standalone application requires to use operating system features such as file system, network, timers, processes, theads, inter-process communication, webview. Features that are not available in the Lua standard libraries.

There are plenty of valuable C modules for various tasks such as _LuaFileSystem_, _luasocket_ and _luv_, even the Lua standard libraries provide some operating system features.
Building upon a specific module may restrict the usage and portability. The idea is to abstract dependent external modules and to provide at least 2 implementations including a pure Lua one if possible.
Higher level APIs are available to provide complex features such as HTTP client and server, Worker.

The luajls module library exposes a set of APIs. These APIs are inspired by JavaScript and Java due to their similarity and their large usage.
The goal is to facilitate the learning and also the usage in combination with JavaScript for example when using an HTTP server or a WebView.
The goal is to expose already existing, well-known APIs for example the handling of asynchronous tasks uses the Promise/A+ specification which is now part of JavaScript.
The APIs support asynchronous operations to ease the development with complex features such as an HTTP server or a graphical user interface.


### Main Principles

This set of modules or libraries are meant to be simple, composable.
The conventions are meant to organize and help understanting these libraries.

When the implementation is based on a dependent Lua module, its name is suffixed by a minus `'-'` character followed by the dependent Lua module name.
By example, to provide the file system API luajls could use the _luafilesystem_, named _lfs_, or the _luv_ dependency.
There are two corresponding bridge implementations _fs-lfs_ and _fs-luv_ exposing the same API.
The main module named _fs_ will load the first available module.


### Name Convention

The library uses the following naming convention:

* Classes are nouns in upper camel case,
such as _Vehicle_, _Bus_
* Methods are verbs in lower camel case,
such as _getColor_, _setRegistrationYear_
* Instances, variables and package names are also written in lower camel case,
such as _myCar_, _aBus_
* Constants are written in uppercase characters separated by underscores,
such as *MAX_HEIGHT*
* Private fields and methods starts with an underscore,
such as *_internal*
* Acronyms are treated as normal words,
such as _Html_, _Url_

Source code is indented using 2 spaces.


# Basic Concepts

This section introduces basic concepts used in the luajls library.

## Namespace and Modules

The library is available under the _jls_ namespace to avoid conflicts, the modules are under packages for organizational purpose to allow the use of small modules without polluting a single directory.

The following packages are available.

* _jls.lang_
Base modules including class definition, module loading, logging, event loop, promise, process, thread
* _jls.io_
File system manipulation, file I/O, pipe, serial, streams
* _jls.net_
Network modules including TCP and UDP socket, HTTP, MQTT, WebSocket
* _jls.util_
utility modules for List and Map, date and time, JSON and XML formats, AST, deflate, ZIP and tar files, scheduling, worker and web view

A `jls` module is provided to automatically load jls modules.

```lua
local jls = require('jls')
print(jls.lang.system.currentTimeMillis()) -- prints the current time in ms
```


## Object-Oriented Programming

The API is mainly exposed via classes, a required class module could be instanciated using the method _new_.

```lua
local Path = require('jls.io.Path')
local configPath = Path:new('work/config.json')
print(configPath:getName()) -- prints 'config.json'
```

A class can exposed fields and methods which are not shared with the instance prototype.

```lua
local Url = require('jls.net.Url')
local urlTable = Url.parse('http://www.lua.org/')
print(urlTable.host) -- prints 'www.lua.org'
```

A class can implement an _initialize_ method that will be called for new instances.
A class can implement prototype methods shared among all its instances.

```lua
local class = require('jls.lang.class')
local Person = class.create(function(person)
  function person:initialize(name)
    self.name = name
  end
  function person:getName()
    return self.name
  end
end)
local luke = Person:new('Luke')
print(luke:getName()) -- prints 'Luke'
```

A class can inherit from another class, prototype methods are inherited by the subclasses.
You could create a class that inherit another class by providing this super class to the _create_ method.

```lua
local class = require('jls.lang.class')
local Vehicle = class.create()
local Car = class.create(Vehicle)
local car = Car:new()
print(Vehicle:isInstance(car)) -- prints true
```

The class can be called directly to create a new instance.

A class can implement:

* an _equals_ method that will be called to test equality using `==`,
* a _length_ method that will be called for the length operator `#`,
* a _toString_ method that will be called by `tostring`.

```lua
local class = require('jls.lang.class')
local Person = class.create(function(person)
  function person:initialize(name)
    self.name = name
  end
  function person:equals(p)
    return self.name == p.name
  end
  function person:length()
    return #self.name
  end
  function person:toString()
    return self.name
  end
end)
local luke = Person('Luke')
print(luke, #luke, luke == Person('Luke')) -- prints 'Luke 4 true'
```


## Exception

The exception class groups the error message and the associated stack.
It provides a common way to deal with errors.
`Promise`, `EventPublisher` and `Thread` call functions and wrap Lua error in Exception.

```lua
local Exception = require('jls.lang.Exception')
local e = Exception('ouch')
print('message:', e:getMessage()) -- prints 'ouch'
print(e) --[[ prints the name, the message and the stack trace:
jls.lang.Exception: ouch
stack traceback:
        (command line):2: in main chunk
        [C]: in ?
]]
e:throw() -- raise the error e
```

For example, a promise needs to call the fulfillment and rejection handlers in protected mode and properly reject in case of error.
At this time, we do not know if the caller is interested by the stack or just the error message.
With the exception, the caller could later decide to use only the error message or to print the stack trace.

The `Exception.getMessage` function unwraps, if necessary, the error message.

The `Exception.pcall` function is similar to the Lua function, except that it returns an exception instance.

An exception may have a cause, allowing to preserve this information when you do not want to rethrow the exception.

Additionnaly, it is possible to create specialized sub class of exception.


## Concurrent Programming

### Event Loop

In order to deal with blocking I/O operations such as getting a network resource, luajls provides an event loop. Blocking operations take a callback function as argument that will be called when the operation completes or when data shall be processed.

The callbacks use the error-first style, such as `function(err, value) ... end`, for both promise and stream more on that later.

If you need to do something after 1 second, you could do it synchronously.

```lua
local system = require('jls.lang.system')
print('Do this first')
system.sleep(1000) -- block
print('Do that after 1 second')
```

It works fine, but you are limited to a single blocking operation, here you can only sleep.
Using the event loop you could compose multiple asynchonous operations

```lua
local event = require('jls.lang.event')
event:setTimeout(function()
  print('Do that after 1 second')
end, 1000)
print('Do this first')
event:loop() -- block
```

So it is quite common to see Lua code ending with the event loop.

Waiting is a trivial example, one could think about 2 non cooperative blocking tasks
such as downloading a file while processing another one.


### Promise

To synchronize the program execution when dealing with asynchronous operations, the library provides an implementation of Promise. This allows to simplify the writing and reading of asynchronous operations compared to callback function.

```lua
local event = require('jls.lang.event')
local Promise = require('jls.lang.Promise')

local function wait(millis)
  return Promise:new(function(resolve, reject)
    event:setTimeout(resolve, millis)
  end)
end

wait(1000):next(function()
  print('Do that after 1 second')
  return wait(1000)
end):next(function()
  print('Do that after another second')
end)
event:loop()
```

You also benefits of the whole Promise API, such as executing multiple parallel promises.

```lua
local event = require('jls.lang.event')
local Promise = require('jls.lang.Promise')

local function wait(millis)
  return Promise:new(function(resolve, reject)
    event:setTimeout(resolve, millis)
  end)
end

Promise.all({wait(500), wait(1000)}):next(function()
  print('Do that after 1 second') -- after both promises are completed
end)

Promise.race({wait(1500), wait(1000)}):next(function()
  print('Do that after 1 second') -- after the first completed promise
end)

event:loop()
```


### Async/Await

The `async` and `await` functions allows asynchronous/non-blocking functions to be written in a traditional synchronous/blocking style.

```lua
local event = require('jls.lang.event')
local Promise = require('jls.lang.Promise')

local function incrementLater(n, millis) -- asynchronous function that return a promise that will resolve after a timeout
  return Promise:new(function(resolve)
    event:setTimeout(resolve, millis or 0, n + 1)
  end)
end

Promise.async(function(await) -- async itself is asynchronous and return a promise
  local n = await(incrementLater(1, 1000)) -- await will block then return 2 after 1 second
  print(await(incrementLater(n, 1000))) -- prints 3 after another second
end)

event:loop()
```


### Stream, Stream Handler

Some asynchronous operations let you read data, such as reading on a network socket.
Luajls provide a stream handler class that will be called as soon as new data is available.
The stream handler is an enhancement of the simple stream callback function.
The stream handler interface could be used on files, pipes, network sockets.

```lua
local StreamHandler = require('jls.io.StreamHandler')
local FileStreamHandler = require('jls.io.streams.FileStreamHandler')

local std = StreamHandler:new(function(_, data)
  if data then
    io.stdout:write(data)
  end
end, function(_, err)
  io.stderr:write(err or 'Stream error')
end)

FileStreamHandler.readAll('./README.md', std)
require('jls.lang.event'):loop()
```

A stream handler could be a simple callback function that will receive data or error.
The function could also receive extra arguments in case of success.

```lua
local StreamHandler = require('jls.io.StreamHandler')
local FileStreamHandler = require('jls.io.streams.FileStreamHandler')

local std = StreamHandler:new(function(err, data, ...)
  if err then
    io.stderr:write(err or 'Stream error')
  elseif data then
    io.stdout:write(data)
  end
end)

FileStreamHandler.readAll('./README.md', std)
require('jls.lang.event'):loop()
```


# Data Storage and Transformation

## File System

This section introduces the main classes allowing to manipulate the file system.

### Path

A path instance lets you manipulates paths in an OS independent manner.

```lua
local Path = require('jls.io.Path')
local workPath = Path:new('work')
local configPath = Path:new(workPath, 'config.json')
print(configPath:getPathName()) -- prints 'work/config.json'
```

### File

A file adds the ability to interact with the file system, such as getting the file type or size, listing the files in a directory or deleting a file.

```lua
local File = require('jls.io.File')
local dir = File:new('.')
for _, file in ipairs(dir:listFiles()) do
  if file:isFile() then
    print('The file "'..file:getPath()..'" length is '..tostring(file:length()))
  end
end
```

### File I/O

A file descriptor allows to create, read from and write into a file.

```lua
local FileDescriptor = require('jls.io.FileDescriptor')
FileDescriptor.open('./README.md', 'r'):next(function(fileDesc)
  return fileDesc:read(256):next(function(data)
    print(data)
    fileDesc:close()
  end)
end)
require('jls.lang.event'):loop()
```

The methods could also be used synchronously for the sake of simplicity and when the blocking time is small and event based operations inconvenient to use.

```lua
local FileDescriptor = require('jls.io.FileDescriptor')
local fileDesc = FileDescriptor.openSync('./README.md', 'r')
local data = fileDesc:readSync(256)
print(data)
fileDesc:closeSync()
```


## Data Transformation

### Codec

The codec class allows to encode or decode a string into another string.
The codec also provides a encoding/decoding stream handlers.
The available codec are Base64, Hexadecimal(hex), cipher, deflate and GZip.

```lua
local codec = require('jls.util.Codec').getInstance('Base64')
print(codec:encode('Hello !')) -- prints 'SGVsbG8gIQ=='
```


### Message Digest

The message digest class allows to transform a string into a string with a fixed size.
You provide the input string by successive calls to update then get the output string by calling digest. 
The available hash algorithms are MD5, SHA-1, CRC32.

```lua
local md = require('jls.util.MessageDigest').getInstance('MD5')
md:update('The quick brown fox jumps over the lazy dog'):digest()
```


# Network Programming

This section introduces the main classes to interact with the network.

## Network Socket

### Transmission Control Protocol (TCP)

The Transmission Control Protocol (TCP) is a connection-oriented communication protocol part of the Internet Protocol (IP) suite.
A connection between client and server is established before data can be sent.
The connection will resolve the specified address.

```lua
local TcpSocket = require('jls.net.TcpSocket')
local client = TcpSocket:new()
client:connect('www.lua.org', 80):next(function()
  client:readStart(function(err, data)
    if data then
      print('Received "'..tostring(data)..'"')
    end
    client:readStop()
    client:close()
  end)
  client:write('GET / HTTP/1.0\r\n\r\n')
end)
require('jls.lang.event'):loop()
```

The TCP server lets you bind on a specific port and accept connections.

```lua
local TcpSocket = require('jls.net.TcpSocket')
local server = TcpSocket:new()
server:bind('127.0.0.1', 80)
function server:onAccept(client)
  print('client connected')
  -- read / write on client
  client:close()
  server:close()
end
require('jls.lang.event'):loop()
```


### User Datagram Protocol (UDP)

The User Datagram Protocol (UDP) is a connectionless communication protocol part of the Internet Protocol (IP) suite.

```lua
local UdpSocket = require('jls.net.UdpSocket')
local host, port = '225.0.0.37', 12345
local receiver = UdpSocket:new()
local sender = UdpSocket:new()
receiver:bind('0.0.0.0', port, {reuseaddr = true})
receiver:joinGroup(host, '0.0.0.0')
receiver:receiveStart(function(err, data, addr)
  print('received data:', data, 'from:', addr.ip, addr.port)
  receiver:receiveStop()
  receiver:close()
end)
sender:send('Hello', host, port):finally(function()
  sender:close()
end)
require('jls.lang.event'):loop()
```

## Hypertext Transfer Protocol (HTTP)

The library provides HTTP 1.1 and 2 client and server.

### HTTP Client

The HTTP client lets you send HTTP requests.

```lua
local HttpClient = require('jls.net.http.HttpClient')

local client = HttpClient:new('http://www.lua.org/')
client:fetch('/'):next(function(response)
  print('status code is', response:getStatusCode())
  return response:text()
end):next(function(body)
  print('body size is', #body)
  client:close()
end)

require('jls.lang.event'):loop()
```


### HTTP Server

The HTTP server allows you to serve any kind of resource.

You create a context associating a path to an handler.
The path is where the resource will be accessible.
The handler will be called each time the server has been contacted on the path.
The path is a pattern and allows to capture part of the path.

```lua
local HttpServer = require('jls.net.http.HttpServer')
local httpServer = HttpServer:new()
httpServer:bind('::', 8080)
httpServer:createContext('/', function(exchange)
  local response = exchange:getResponse()
  response:setBody('It works !')
end)
require('jls.lang.event'):loop()
```

The library provides basic HTTP handlers for various tasks, accessing files, proxy resources.
A basic use case is to serve local files.

```lua
local HttpServer = require('jls.net.http.HttpServer')
local HttpHandler = require('jls.net.http.HttpHandler')
local httpServer = HttpServer:new()
httpServer:bind('::', 8080)
httpServer:createContext('/rest/(.*)', HttpHandler.file('.', 'rl'))
require('jls.lang.event'):loop()
```

Another use case is to expose a HTTP APIs.

```lua
local HttpServer = require('jls.net.http.HttpServer')
local HttpHandler = require('jls.net.http.HttpHandler')
local httpServer = HttpServer:new()
httpServer:bind('::', 8080)
httpServer:createContext('/(.*)', HttpHandler.rest({
  admin = {
    stop = function(exchange)
      httpServer:close()
      return 'Bye !'
    end
  }
}))
require('jls.lang.event'):loop()
```


### WebSocket

WebSocket is a communication protocol, providing full-duplex communication over a TCP connection.

A common usage is with an HTTP server.

```lua
local HttpServer = require('jls.net.http.HttpServer')
local Map = require('jls.util.Map')
local WebSocket = require('jls.net.http.WebSocket')
local httpServer = HttpServer:new()
httpServer:bind('::', 8080)
httpServer:createContext('/ws/',  Map.assign(WebSocket.UpgradeHandler:new(), {
  onOpen = function(_, webSocket)
    function webSocket:onTextMessage(payload)
      webSocket:sendTextMessage('You said '..payload)
    end
    webSocket:sendTextMessage('Welcome')
  end
}))
require('jls.lang.event'):loop()
```

# Process and Thread

## Process

The library provides classes to launch and interact with processes.

```lua
local ProcessBuilder = require('jls.lang.ProcessBuilder')
local pb = ProcessBuilder:new('lua', '-e', 'os.exit(11)')
pb:start()
```

You could redirect the output to a file descriptor.

```lua
local ProcessBuilder = require('jls.lang.ProcessBuilder')
local FileDescriptor = require('jls.io.FileDescriptor')
local pb = ProcessBuilder:new('lua', '-e', 'print("Hello")')
local fd = FileDescriptor.openSync('output.tmp', 'w')
pb:redirectOutput(fd)
local ph = pb:start()
fd:close()
```


## Thread

A thread allows to execute a Lua function concurrently.
Using threads allows to execute blocking or long processing operations without blocking the main thread.

You could pass parameters to the thread function and retrieve the function return value.
It is not possible to share variables with a thread, so you should take care to not use variable defined outside the thread function.

```lua
local Thread = require('jls.lang.Thread')
Thread:new(function(value)
  return 'Hi '..tostring(value)
end):start('John'):ended():next(function(res)
  print('trhead return value:', res)
end)
require('jls.lang.event'):loop()
```

The Worker class allows to process background tasks, on a dedicated thread.
The two side of the worker can send and receive messages.

```lua
local Worker = require('jls.util.Worker')
local worker = Worker:new(function(w)
  function w:onMessage(message)
    w:postMessage('Hi '..tostring(message))
  end
end)
function worker:onMessage(message)
  print('received from worker:', message)
  self:close()
end
worker:postMessage('John')
require('jls.lang.event'):loop()
```


## Inter-Process Communication

### Pipe

A pipe allows to communicate between processes or threads.

#### Anonymous Pipe

You could redirect the process standard output to a pipe.

```lua
local ProcessBuilder = require('jls.lang.ProcessBuilder')
local Pipe = require('jls.io.Pipe')
local pb = ProcessBuilder:new('lua', '-e', 'print("Hello")')
local p = Pipe:new()
pb:redirectOutput(p)
local ph = pb:start()
local outputData
p:readStart(function(err, data)
  if data then
    print('Process output:', data)
  else
    p:close()
  end
end)
require('jls.lang.event'):loop()
```

#### Named Pipe

Named pipes are only available with the _luv_ module.

```lua
local Pipe = require('jls.io.Pipe')
local pipeName = Pipe.normalizePipeName('test')
local p = Pipe:new()
function p:onAccept(pb)
  local status, err = pb:readStart(function(err, data)
    if data then
      pb:write('Hi '..tostring(data))
    else
      pb:close()
      p:close()
    end
  end)
end
p:bind(pipeName):next(function()
  local pc = Pipe:new()
  pc:connect(pipeName):next(function()
    local status, err = pc:readStart(function(err, data)
      print('Pipe client received:', data)
      pc:close()
    end)
    pc:write('John')
  end)
end)
require('jls.lang.event'):loop()
```

### Message Passing

The Channel class provides a local message passing interface suitable for process and thread event based message passing.

The messages are sent and received as string on a channel.
The goal is to abstract the message transport implementation, that can internally be a queue, a pipe or a socket.

The channel resource is represented by an opaque string and can be generated automatically.
Internally using URI with authentication keys, pipe://pub.priv@local/p12345 or tcp://pub.priv@localhost:12345.

This interface is used for worker that abstract the thread.

```lua
local Channel = require('jls.util.Channel')
local channelServer = Channel:new()
channelServer:acceptAndClose():next(function(acceptedChannel)
  acceptedChannel:receiveStart(function(message)
    print(message)
    acceptedChannel:close()
  end)
end)
local channel = Channel:new()
channelServer:bind():next(function()
  local name = channelServer:getName() -- after bind the server provides a name for the connection
  return channel:connect(name)
end):next(function()
  channel:writeMessage('Hello')
end)
require('jls.lang.event'):loop()
```


# Utilities

The library comes with various utilities.

## Basic Classes

This section presents the classes that extend the Lua basic types.

### StringBuffer

The StringBuffer class represents a mutable string, optimizing the addition of strings in a buffer by avoiding the use of intermediary concatenated string.

```lua
local StringBuffer = require('jls.lang.StringBuffer')
local buffer = StringBuffer:new('a', 'b')
buffer:append('c', 'd')
print(buffer:toString())
-- prints 'abcd'
```

### Table List

The List and Map classes are drop in replacements for table, adding instance methods.

```lua
local List = require('jls.util.List')
local list = List:new('a', 'b')
local newList = list:map(function(v, i)
  return v..tostring(i)
end)
-- {'a1', 'b2'}
```

The List instances are fully compatible with Lua sequence table.
The Map provides a `getTable()` method to access a fully compatible table map.

### Table Map

The List and Map class methods can be used directly with Lua tables.

```lua
local Map = require('jls.util.Map')
for k, v in Map.spairs({a = 1, c = 3, b = 2}) do
  print(k, v)
end
```

### Date and Time

The LocalDateTime class deals with date and time without considering the time zone.

```lua
local LocalDateTime = require('jls.util.LocalDateTime')
local localDateTime = LocalDateTime:new(2001, 10, 21, 13, 30, 0)
print(localDateTime:toISOString())
-- prints '2001-10-21T13:30:00.000'
```

The Date class represents a date in the default or UTC time zone.

```lua
local Date = require('jls.util.Date')
local date = Date:new()
print(date:toLocalDateTime():toISOString())
-- prints the current date in ISO format
```

### Tables

The _tables_ module contains helper functions to manipulate Lua deep tables.

It allows to serialize a Lua table into a string and materialize from.

```lua
local tables = require("jls.util.tables")
print(tables.stringify({a = "Hi"}))
-- prints '{a="Hi",}'
local t = tables.parse('{a="Hi",b=2,c=true}')
-- t is {a = "Hi", b = 2, c = true}
```


## Data Exchange Formats

The library contains various data exchange formats, such as JSON and XML.

### JavaScript Object Notation (JSON)

The _json_ module allows to serialize a Lua table into a string and materialize from.

```lua
local json = require('jls.util.json')
print(json.stringify({aString = 'Hi', anInteger = 321, aNumber = 3.21, aBoolean = false}))
-- prints '{"aBoolean":false,"aNumber":3.21,"aString":"Hi","anInteger":321}'

local t = json.parse('{"aBoolean":false,"aNumber":3.21,"aString":"Hi","anInteger":321}')
-- t contains the expected table 
```

### Extensible Markup Language (XML)

The XML nodes are represented using table for elements and string for texts.
The table is used as an array to store the XML node children.
The table has the properties 'name' and optionally 'attr' to store
the node name and the node attributes using a table with key value pairs.

```lua
local xml = require('jls.util.xml')
print(xml.encode({name = 'a', {name = 'b', attr = {c = 'c'}, 'A value'}}))
-- prints '<a><b c="c">A value</b></a>'

local t = xml.decode('<a><b c="c">A value</b></a>')
-- t contains {name = 'a', {name = 'b', attr = {c = 'c'}, 'A value'}}
```


## Abstract Syntax Tree (AST)

The _ast_ module allows to parse and generate Lua code.

```lua
local ast = require('jls.util.ast')
local tree = ast.parse("local a = 2 // 2")
print(ast.generate(tree))
-- prints 'local a=2//2;'
```


## User Interface

The library does not provide native nor toolkit based user interfaces.

### WebView

The WebView class allow to display HTML content in a window.

Many OSes come with a default webview allowing simplifying the creation of user interface.

The WebView highly depends on the underlying OS.
Opening multiple WebView windows is not supported.

A webview requires a thread to run its own event loop, which is not compatible with the base event loop.
This class provide helpers to start webview in a dedicated thread so that the base event loop can be used.

You could use the WebView with a synchronous callback for simple use cases.
As soon as you need to tackle more complex use cases you will need threads and communication.
The recommended way is to use an HTTP server as it is the default way to do web application.

```lua
local WebView = require('jls.util.WebView')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
WebView.open('http://localhost:0/index.html'):next(function(webview)
  local httpServer = webview:getHttpServer()
  httpServer:createContext('/(.*)', FileHttpHandler:new('htdocs'))
end)
require('jls.lang.event'):loop()
```
