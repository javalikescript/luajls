--- zip handler
local httpHandlerBase = require('jls.net.http.handler.base')
local httpHandlerUtil = require('jls.net.http.handler.util')
local File = require('jls.io.File')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST

--- Exposes ZIP file content.
-- The ZIP file is specified using the attribute zipFile
-- @tparam jls.net.http.HttpExchange httpExchange ongoing HTTP exchange
-- @function zip
local function zip(httpExchange)
  local response = httpExchange:getResponse()
  local context = httpExchange:getContext()
  local zipFile = context:getAttribute('zipFile')
  if not zipFile then
    httpHandlerBase.internalServerError(httpExchange)
    return
  end
  local path = httpExchange:getRequestArguments()
  local entry = zipFile:getEntry(path)
  if entry then
    local content = zipFile:getContent(entry)
    response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
    response:setContentType(httpHandlerUtil.guessContentType(path))
    response:setCacheControl(true)
    response:setContentLength(#content)
    response:setBody(content)
  else
    httpHandlerBase.notFound(httpExchange)
  end
end

return zip
