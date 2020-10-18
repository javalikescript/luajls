--- Basic file handler
local logger = require('jls.lang.logger')
local httpHandlerBase = require('jls.net.http.handler.base')
local httpHandlerUtil = require('jls.net.http.handler.util')
local File = require('jls.io.File')
local setMessageBodyFile = require('jls.net.http.setMessageBodyFile')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST

--- Basic file handler.
-- Serve static files.
-- The files are looked up from attribute rootFile or rootPath.
-- @tparam jls.net.http.HttpExchange httpExchange ongoing HTTP exchange
-- @function file
local function file(httpExchange)
  local response = httpExchange:getResponse()
  local context = httpExchange:getContext()
  local rootFile = context:getAttribute('rootFile')
  if not rootFile then
    rootFile = File:new(context:getAttribute('rootPath') or '.')
    context:setAttribute('rootFile', rootFile)
  end
  local path = httpExchange:getRequestArguments()
  if not httpHandlerUtil.isValidSubPath(path) then
    httpHandlerBase.forbidden(httpExchange)
    return
  end
  path = string.gsub(path, '/$', '')
  if path == '' then
    path = context:getAttribute('defaultFile') or 'index.html'
  end
  local file = File:new(rootFile, path)
  if file:isDirectory() then
    file = File:new(file, context:getAttribute('defaultFile') or 'index.html')
  end
  if file:isFile() then
    response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
    local extension = file:getExtension()
    response:setContentType(httpHandlerUtil.CONTENT_TYPES[extension] or httpHandlerUtil.CONTENT_TYPES.bin)
    response:setCacheControl(true)
    response:setContentLength(file:length())
    setMessageBodyFile(response, file)
  else
    if logger:isLoggable(logger.FINE) then
      logger:fine('The resource "'..httpExchange:getRequest():getTarget()..'" is not available for file '..file:getPath()..'.')
    end
    response:setStatusCode(HTTP_CONST.HTTP_NOT_FOUND, 'Not Found')
    response:setBody('<p>The resource "'..httpExchange:getRequest():getTarget()..'" is not available.</p>')
  end
end

return file