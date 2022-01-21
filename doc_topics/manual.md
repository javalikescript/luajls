# Introduction

## Audience

This document is intended for Lua users wanting to use and understand the luajls library, more broadly to people developping standalone Lua application.
It is presumed that the reader has a good knowledge of Lua, please consult the Lua [reference manual](https://www.lua.org/manual/5.4/manual.html) and [Programming in Lua](https://www.lua.org/pil/) to learn details regarding Lua itself.


## Overview

luajls is a set of Lua modules for developing stand-alone [Lua](https://www.lua.org/) applications.

The modules provide general-purpose functions such as class definition and promise, to operating system abstractions such as file system and network access. The modules support asynchronous I/O based on an event loop.

The modules expose an API to abstract the host platform and general purpose libraries such as _SSL_, _JSON_, _XML_, _ZIP_.
The main targeted OSes are _Linux_ and _Windows_.

The only required dependency is Lua 5.4

Optional dependencies are C and Lua modules such as _luafilesystem_, _luasocket_, _luv_, _lua-openssl_, _lua-cjson_.
By example, the file system manipulation requires one of the _luafilesystem_ or the _luv_ dependent module.

See [Lua JLS repository](https://github.com/javalikescript/luajls)
and the [Lua C libraries repository](https://github.com/javalikescript/luaclibs)


## General Considerations

### Motivations and Reasoning

The motivation is to facilitate the development of complex standalone applications.

Building standalone application requires to use operating system features such as file system, network, timers, processes, theads, inter-process communication, webview. Features that are not available in the Lua standard libraries.

There are plenty of valuable C modules for various tasks such as _LuaFileSystem_, _luasocket_ and _luv_, even the Lua standard libraries provide some operating system features.
Building upon a specific module may restrict the usage and portability. The idea is to abstract dependent external modules and to provide at least 2 implementations including a pure Lua one if possible.
Accessing OS features is not enough, a higher level language is required to provide complex features such as HTTP client and server, Worker.

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
Utility modules for List, Map, date and time, JSON and XML formats, deflate, ZIP file, worker and WebView


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

## Concurrent Programming

## Event Loop

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


### Stream, Stream Handler

Some asynchronous operations let you read data, such as reading on a network socket.
Luajls provide a stream handler class that will be called as soon as new data is available.
The stream handler is an enhancement of the simple stream callback function.
The stream handler interface could be used on files, pipes, network sockets.

```lua
local StreamHandler = require('jls.io.streams.StreamHandler')
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

```lua
local StreamHandler = require('jls.io.streams.StreamHandler')
local FileStreamHandler = require('jls.io.streams.FileStreamHandler')

local std = StreamHandler:new(function(err, data)
  if err then
    io.stderr:write(err or 'Stream error')
  elseif data then
    io.stdout:write(data)
  end
end)

FileStreamHandler.readAll('./README.md', std)
require('jls.lang.event'):loop()
```

# Data Storage

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


# Network Programming

This section introduces the main classes to interact with the network.

## Network Socket

### Transmission Control Protocol (TCP)

The Transmission Control Protocol (TCP) is one of the main protocols of the Internet protocol suite.
The connection will resolve the specified address.

```lua
local TcpClient = require('jls.net.TcpClient')
local client = TcpClient:new()
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
local TcpServer = require('jls.net.TcpServer')
local server = TcpServer:new()
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

```lua
local UdpSocket = require('jls.net.UdpSocket')
local host, port = '225.0.0.37', 12345
local receiver = UdpSocket:new()
local sender = UdpSocket:new()
receiver:bind('0.0.0.0', port, {reuseaddr = true})
receiver:joinGroup(host, '0.0.0.0')
receiver:receiveStart(function(err, data)
  print('received data:', data)
  receiver:receiveStop()
  receiver:close()
end)
sender:send('Hello', host, port):finally(function()
  sender:close()
end)
require('jls.lang.event'):loop()
```

## Hypertext Transfer Protocol (HTTP)

The library provides HTTP 1.1 client and server.

### HTTP Client

The HTTP client lets you send HTTP requests.

```lua
local HttpClient = require('jls.net.http.HttpClient')

local client = HttpClient:new({url = 'http://www.lua.org/'})
client:connect():next(function()
  return client:sendReceive()
end):next(function(response)
  client:close()
  return response:getBody()
end):next(function(body)
  print('body size', #body)
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
httpServer:createContext('/', function(httpExchange)
  local response = httpExchange:getResponse()
  response:setBody('It works !')
end)
require('jls.lang.event'):loop()
```

The library provides basic HTTP handlers for various tasks, accessing files, proxy resources.
A basic use case is to serve local files.

```lua
local HttpServer = require('jls.net.http.HttpServer')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local httpServer = HttpServer:new()
httpServer:bind('::', 8080)
httpServer:createContext('/rest/(.*)', FileHttpHandler:new('.', 'rl'))
require('jls.lang.event'):loop()
```

Another use case is to expose a HTTP APIs.

```lua
local HttpServer = require('jls.net.http.HttpServer')
local RestHttpHandler = require('jls.net.http.handler.RestHttpHandler')
local httpServer = HttpServer:new()
httpServer:bind('::', 8080)
httpServer:createContext('/(.*)', RestHttpHandler:new({
  admin = {
    stop = function(httpExchange)
      httpServer:close()
      return 'Bye !'
    end
  end
}))
require('jls.lang.event'):loop()
```

### WebSocket

WebSocket is a communication protocol, providing full-duplex communication over a TCP connection.

A common usage is with an HTTP server.

```lua
local HttpServer = require('jls.net.http.HttpServer')
local Map = require('jls.util.Map')
local WebSocketUpgradeHandler = require('jls.net.http.ws').WebSocketUpgradeHandler
local httpServer = HttpServer:new()
httpServer:bind('::', 8080)
httpServer:createContext('/ws/',  Map.assign(WebSocketUpgradeHandler:new(), {
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
event:loop()
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

### Table Map

The List and Map classes are compatibles with Lua tables, so the class methods can be used directly with Lua tables.

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

## User Interface

The library does not provide native nor toolkit based user interfaces.

### WebView

The WebView class allow to display HTML content in a window.

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