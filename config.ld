-- See https://stevedonovan.github.io/ldoc/manual/doc.md.html
file = {'jls', exclude = {
  'jls/io/streams',
  'jls/net/http/filter',
  'jls/net/http/handler',
  'jls/net/http/Hpack.lua',
  'jls/util/CoroutineScheduler.lua',
  'jls/util/Struct.lua',
}}
project = "luajls"
title = "Lua JLS 0.7"
description = "luajls documentation"
full_description = [[
The luajls library provides abstraction interfaces for general-purpose scripting.

## Contents

* Introduction
    * @{manual.md.Audience|Audience}
    * @{manual.md.Overview|Overview}
    * @{manual.md.General_Considerations|General Considerations}
* Basic Concepts
    * @{manual.md.Namespace_and_Modules|Namespace and Modules}
    * @{manual.md.Object_Oriented_Programming|Object Oriented Programming}
    * @{manual.md.Exception|Exception}
    * @{manual.md.Concurrent_Programming|Concurrent Programming}
* Data Storage and Transformation
    * @{manual.md.File_System|File System}
    * @{manual.md.Data_Transformation|Data Transformation}
* Network Programming
    * @{manual.md.Network_Socket|Network Socket}
    * @{manual.md.Hypertext_Transfer_Protocol__HTTP_|Hypertext Transfer Protocol (HTTP)}
* Process and Thread
    * @{manual.md.Process|Process}
    * @{manual.md.Thread|Thread}
    * @{manual.md.Inter_Process_Communication|Inter-Process Communication}
* Utilities
    * @{manual.md.Basic_Classes|Basic Classes}
    * @{manual.md.Data_Exchange_Formats|Data Exchange Formats}
    * @{manual.md.User_Interface|User Interface}

]]
--no_return_or_parms = true
--no_summary = true
--no_space_before_args = true 
--sort = true
style = "!fixed"
--no_lua_ref = true
topics = "doc_topics"
package = "jls"
format = "markdown"
custom_tags = {
    {'experimental', title='Experimental Section'},
}