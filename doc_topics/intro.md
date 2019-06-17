## Overview

Luajls is a standard library for lua.

The library provides an abstract interface to the underlying operating system, such as file system and network.
The jls lua library includes a set of lua modules providing an API to abstract the host platform. The main targeted OSes are Linux and Windows.
The only required dependency is lua 5.3 Other dependencies are lua native modules such as lfs, luasocket, luv, lua-openssl, lua-cjson.

see [javalikescript/lua](http://javalikescript.free.fr/lua/)


## Features

The following packages are available.

* _jls.io_
File system manipulation, file channel, pipe, serial
* _jls.lang_
Base classes including class definition, module loading, logging, event loop, promises, process
* _jls.net_
Network classes including TCP and UDP socket, HTTP, MQTT WebSocket client and server
* _jls.util_
Utility classes for date and time, json format, deflate and zip file, structs


## Name Convention

The naming convention used is the following:
Classes should be nouns in upper camel case, such as Vehicle, Bus.
Methods should be verbs in lower camel case, such as getColor, setRegistrationYear.
Instances, variables and package names are also written in lower camel case, such as myCar, aBus.
Constants should be written in uppercase characters separated by underscores, such as MAX_HEIGHT.
Private fields and methods should start with an underscore.


## Main principles

This set of modules or libraries are meant to be simple, composable.
The conventions are meant to organize and help understanting these libraries.
