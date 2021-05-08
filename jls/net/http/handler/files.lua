-- Deprecated, will be removed

local httpHandlerBase = require('jls.net.http.handler.base')
local httpHandlerUtil = require('jls.net.http.handler.util')
local json = require('jls.util.json')
local File = require('jls.io.File')
local setMessageBodyFile = require('jls.net.http.setMessageBodyFile')
local FileStreamHandler = require('jls.io.streams.FileStreamHandler')
local StreamHandler = require('jls.io.streams.StreamHandler')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST

local function handleGetFile(httpExchange, file)
  local response = httpExchange:getResponse()
  response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
  response:setContentType(httpHandlerUtil.CONTENT_TYPES.bin)
  response:setCacheControl(false)
  response:setContentLength(file:length())
  setMessageBodyFile(response, file)
end

local function handleGetDirectory(httpExchange, file, showParent)
  local response = httpExchange:getResponse()
  local filenames = file:list()
  local body = ''
  local request = httpExchange:getRequest()
  --local accept = request:getHeader('Accept')
  --if accept and string.find(accept, httpHandlerUtil.CONTENT_TYPES.json) then
  if request:hasHeaderValue(HTTP_CONST.HEADER_ACCEPT, httpHandlerUtil.CONTENT_TYPES.json) then
    local dir = {}
    for i, filename in ipairs(filenames) do
      local f = File:new(file, filename)
      table.insert(dir, {
        name = filename,
        isDirectory = f:isDirectory()
      })
    end
    body = json.encode(dir)
    response:setContentType(httpHandlerUtil.CONTENT_TYPES.json)
  else
    if showParent then
      body = '<a href="..">..</a><br/>\n'
    end
    for i, filename in ipairs(filenames) do
      local f = File:new(file, filename)
      if f:isDirectory() then
        filename = filename..'/'
      end
      body = body..'<a href="'..filename..'">'..filename..'</a><br/>\n'
    end
    response:setContentType(httpHandlerUtil.CONTENT_TYPES.html)
  end
  response:setCacheControl(false)
  response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
  response:setBody(body)
end

local function files(httpExchange)
  local request = httpExchange:getRequest()
  local context = httpExchange:getContext()
  local rootFile = context:getAttribute('rootFile')
  if not rootFile then
    rootFile = File:new(context:getAttribute('rootPath') or '.')
    context:setAttribute('rootFile', rootFile)
  end
  local method = string.upper(request:getMethod())
  --local path = httpExchange:getRequest():getTarget()
  local path = httpExchange:getRequestArguments()
  local isDirectoryPath = string.sub(path, -1) == '/'
  local filePath = isDirectoryPath and string.sub(path, 1, -2) or path
  if filePath == '' and method ~= HTTP_CONST.METHOD_GET or not httpHandlerUtil.isValidSubPath(path) then
    httpHandlerBase.forbidden(httpExchange)
    return
  end
  local file = File:new(rootFile, filePath)
  -- TODO Handle HEAD as a GET without body
  -- TODO Handle PATCH, MOVE
  if method == HTTP_CONST.METHOD_GET then
    if file:isFile() then
      handleGetFile(httpExchange, file)
    elseif file:isDirectory() then
      handleGetDirectory(httpExchange, file, true)
    else
      httpHandlerBase.notFound(httpExchange)
    end
  elseif method == HTTP_CONST.METHOD_POST then
    if file:isFile() then
      file:write(request:getBody()) -- TODO Handle errors
      httpHandlerBase.ok(httpExchange)
    else
      httpHandlerBase.forbidden(httpExchange)
    end
  elseif method == HTTP_CONST.METHOD_PUT and context:getAttribute('allowCreate') == true then
    if isDirectoryPath then
      file:mkdirs() -- TODO Handle errors
    else
      file:write(request:getBody()) -- TODO Handle errors
    end
    httpHandlerBase.ok(httpExchange)
  elseif method == HTTP_CONST.METHOD_DELETE and context:getAttribute('allowDelete') == true then
    if file:isFile() then
      file:delete() -- TODO Handle errors
    elseif file:isDirectory() then
      file:deleteRecursive() -- TODO Handle errors
    end
    httpHandlerBase.ok(httpExchange)
  else
    httpHandlerBase.methodNotAllowed(httpExchange)
  end
end

return files
