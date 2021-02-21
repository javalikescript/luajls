## Overview

Luajls is a standard library for [Lua](https://www.lua.org/).

The library provides an abstract interface to the underlying operating system, such as file system and network.
The jls Lua library includes a set of jls Lua modules providing an API to abstract the host platform.
The jls Lua library also provides interface for general purpose libraries such as SSL, JSON, ZIP, JPEG.
The main targeted OSes are Linux and Windows.

The only required dependency is Lua 5.4
Optional dependencies are Lua modules such as luafilesystem, luasocket, luv, lua-openssl, lua-cjson.
By example, the file system manipulation requires one of the luafilesystem or the luv dependent module.

See [javalikescript/lua](http://javalikescript.free.fr/lua/),
the [Lua JLS repository](https://github.com/javalikescript/luajls)
and the [Lua C libraries repository](https://github.com/javalikescript/luaclibs)


## Features

The following packages are available.

* _jls.io_
File system manipulation, file channel, pipe, serial
* _jls.lang_
Base modules including class definition, module loading, logging, event loop, promise, process
* _jls.net_
Network modules including TCP and UDP socket, HTTP, MQTT WebSocket client and server
* _jls.util_
Utility modules for date and time, JSON format, deflate, ZIP file and WebView


## Name Convention

The naming convention used is the following:
Classes should be nouns in upper camel case, such as Vehicle, Bus.
Methods should be verbs in lower camel case, such as getColor, setRegistrationYear.
Instances, variables and package names are also written in lower camel case, such as myCar, aBus.
Constants should be written in uppercase characters separated by underscores, such as MAX_HEIGHT.
Private fields and methods should start with an underscore.
Acronyms should be treated as normal words, such as Html, Url.

Source code should be indented using 2 spaces.

## Main principles

This set of modules or libraries are meant to be simple, composable.
The conventions are meant to organize and help understanting these libraries.

When the implementation is based on a dependent Lua module, its name is suffixed by a minus character followed by the dependent Lua module.
By example, to provide the file system APIs luajls could use the _luafilesystem_, named _lfs_, or the _luv_ dependency.
There are two corresponding bridge implementations _fs-lfs_ and _fs-luv_ exposing the same APIs.
The main Lua jls module named _fs_ will load the first available module.
