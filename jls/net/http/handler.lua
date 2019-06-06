
local logger = require('jls.lang.logger')
local net = require('jls.net')
local http = require('jls.net.http')
local Promise = require('jls.lang.Promise')
local File = require('jls.io.File')
local FileDescriptor = require('jls.io.FileDescriptor')
local json = require('jls.util.json')
local base64 = require('jls.util.base64')
local tables = require('jls.util.tables')

--local loader = require('jls.lang.loader')
--local ZipFile = loader.tryRequire('jls.util.zip.ZipFile')

local socketToString = net.socketToString

local HTTP_CONST = http.CONST

local HTTP_CONTENT_TYPES = {
  bin = 'application/octet-stream',
  css = 'text/css',
  js = 'application/javascript',
  json = 'application/json',
  htm = 'text/html',
  html = 'text/html',
  txt = 'text/plain',
  xml = 'text/xml',
  pdf = 'application/pdf'
}


local httpHandler = {}

--- Returns an handler that chain the specified handlers
function httpHandler.chain(...)
  local handlers = {...}
  return function(httpExchange)
    httpExchange:getResponse():setStatusCode(0)
    local result
    for _, handler in ipairs(handlers) do
      result = handler(httpExchange)
      if httpExchange:getResponse():getStatusCode() ~= 0 then
        break
      end
    end
    return result
  end
end

function httpHandler.methodNotAllowed(httpExchange)
  local response = httpExchange:getResponse()
  response:setStatusCode(HTTP_CONST.HTTP_METHOD_NOT_ALLOWED, 'Method Not Allowed')
  response:setBody('<p>Sorry this method is not allowed.</p>')
end

function httpHandler.basicAuthentication(httpExchange)
  local context = httpExchange:getContext()
  local checkCredentials = context:getAttribute('checkCredentials')
  if not checkCredentials then
    local credentials = context:getAttribute('credentials')
    if not credentials then
      logger:warn('httpHandler.basicAuthentication() missing credentials')
      credentials = {}
    end
    checkCredentials = function(user, password)
      return credentials[user] == password
    end
    context:setAttribute('checkCredentials', checkCredentials)
  end
  local request = httpExchange:getRequest()
  local response = httpExchange:getResponse()
  local authorization = request:getHeader(HTTP_CONST.HEADER_AUTHORIZATION)
  if not authorization then
    response:setHeader(HTTP_CONST.HEADER_WWW_AUTHENTICATE, 'Basic realm="User Visible Realm"')
    response:setStatusCode(HTTP_CONST.HTTP_UNAUTHORIZED, 'Unauthorized')
    return
  end
  if logger:isLoggable(logger.FINEST) then
    logger:finest('httpHandler.basicAuthentication() authorization: "'..authorization..'"')
  end
  if string.find(authorization, 'Basic ') == 1 then
    authorization = base64.decode(string.sub(authorization, 7))
    if authorization then
      local user, password = string.match(authorization, '^([^:]+):(.+)$')
      if user then
        if not checkCredentials(user, password) then
          response:setHeader(HTTP_CONST.HEADER_WWW_AUTHENTICATE, 'Basic realm="User Visible Realm"')
          response:setStatusCode(HTTP_CONST.HTTP_UNAUTHORIZED, 'Unauthorized')
          if logger:isLoggable(logger.FINE) then
            logger:fine('httpHandler.basicAuthentication() use "'..user..'" is not authorized')
          end
        end
        return
      end
    end
  end
  response:setStatusCode(HTTP_CONST.HTTP_BAD_REQUEST, 'Bad request')
end

function httpHandler.internalServerError(httpExchange)
  local response = httpExchange:getResponse()
  response:setVersion(HTTP_CONST.VERSION_1_0)
  response:setStatusCode(HTTP_CONST.HTTP_INTERNAL_SERVER_ERROR, 'Internal Server Error')
  response:setBody('<p>Sorry something went wrong on our side.</p>')
end

function httpHandler.notFound(httpExchange)
  local response = httpExchange:getResponse()
  response:setStatusCode(HTTP_CONST.HTTP_NOT_FOUND, 'Not Found')
  response:setBody('<p>The resource "'..httpExchange:getRequest():getTarget()..'" is not available.</p>')
end

function httpHandler.badRequest(httpExchange)
  local response = httpExchange:getResponse()
  response:setStatusCode(HTTP_CONST.HTTP_BAD_REQUEST, 'Bad Request')
  response:setBody('<p>Sorry something seems to be wrong in your request.</p>')
end

function httpHandler.ok(httpExchange, body, contentType)
  local response = httpExchange:getResponse()
  response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
  if type(contentType) == 'string' then
    response:setContentType(contentType)
  end
  if body then
    response:setBody(body)
  end
end

function httpHandler.methodAllowed(httpExchange, method)
  local httpRequest = httpExchange:getRequest()
  if type(method) == 'string' then
    if httpRequest:getMethod() ~= method then
      httpHandler.methodNotAllowed(httpExchange)
      return false
    end
  elseif type(method) == 'table' then
    for _, m in ipairs(method) do
      if not httpHandler.methodAllowed(httpExchange, m) then
        return false
      end
    end
  end
  return true
end

function httpHandler.replyJson(response, t)
  response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
  response:setContentType(HTTP_CONTENT_TYPES.json)
  response:setBody(json.encode(t))
end

local function setMessageBodyFile(response, file, size)
  size = size or 2048
  if logger:isLoggable(logger.FINE) then
    logger:fine('setMessageBodyFile(?, '..file:getPath()..', '..tostring(size)..')')
  end
  function response:writeBody(stream, callback)
    if logger:isLoggable(logger.FINE) then
      logger:fine('setMessageBodyFile() "'..file:getPath()..'" => response:writeBody()')
    end
    local cb, promise = Promise.ensureCallback(callback)
    local fd = FileDescriptor.openSync(file) -- TODO Handle error
    local writeCallback
    writeCallback = function(err)
      if logger:isLoggable(logger.FINER) then
        logger:finer('setMessageBodyFile() "'..file:getPath()..'" => writeCallback('..tostring(err)..')')
      end
      if err then
        fd:closeSync()
        cb(err)
      else
        fd:read(size, nil, function(err, buffer)
          if err then
            fd:closeSync()
            cb(err)
          end
          if buffer then
            if logger:isLoggable(logger.FINER) then
              logger:finer('setMessageBodyFile() "'..file:getPath()..'" => read #'..tostring(#buffer))
            end
            stream:write(buffer, writeCallback)
          else
            fd:closeSync()
            cb()
          end
        end)
      end
    end
    writeCallback()
    return promise
  end
  -- local body = file:readAll()
  -- if body then
  --   response:setBody(body)
  -- end
end

--- Basic file handler
function httpHandler.file(httpExchange)
  local response = httpExchange:getResponse()
  local context = httpExchange:getContext()
  local rootFile = context:getAttribute('rootFile') or File:new('.')
  if not rootFile then
    rootFile = File:new(context:getAttribute('rootPath') or '.')
    context:setAttribute('rootFile', rootFile)
  end
  local path = httpExchange:getRequestArguments()
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
    response:setContentType(HTTP_CONTENT_TYPES[extension] or HTTP_CONTENT_TYPES.bin)
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

local function handleGetFile(httpExchange, file)
  local response = httpExchange:getResponse()
  response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
  response:setContentType(HTTP_CONTENT_TYPES.bin)
  response:setCacheControl(false)
  response:setContentLength(file:length())
  setMessageBodyFile(response, file)
end

local function handleGetDirectory(httpExchange, file)
  local response = httpExchange:getResponse()
  local filenames = file:list()
  local body = ''
  local request = httpExchange:getRequest()
  local accept = request:getHeader('Accept')
  if accept and string.find(accept, HTTP_CONTENT_TYPES.json) then
    local dir = {}
    for i, filename in ipairs(filenames) do
      local f = File:new(file, filename)
      table.insert(dir, {
        name = filename,
        isDirectory = f:isDirectory()
      })
    end
    body = json.encode(dir)
    response:setContentType(HTTP_CONTENT_TYPES.json)
  else
    for i, filename in ipairs(filenames) do
      local f = File:new(file, filename)
      if f:isDirectory() then
        filename = filename..'/'
      end
      body = body..'<a href="'..filename..'">'..filename..'</a><br/>\n'
    end
    response:setContentType(HTTP_CONTENT_TYPES.html)
  end
  response:setCacheControl(false)
  response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
  response:setBody(body)
end

--- Files handler that can list directories, delete and put files
function httpHandler.files(httpExchange)
  local request = httpExchange:getRequest()
  local context = httpExchange:getContext()
  local rootFile = context:getAttribute('rootFile') or File:new('.')
  if not rootFile then
    rootFile = File:new(context:getAttribute('rootPath') or '.')
    context:setAttribute('rootFile', rootFile)
  end
  local method = string.upper(request:getMethod())
  --local path = httpExchange:getRequest():getTarget()
  local path = httpExchange:getRequestArguments()
  path = string.gsub(path, '/$', '')
  local file = File:new(rootFile, path)
  -- TODO Handle HEAD as a GET without body
  -- TODO Handle PATCH, MOVE
  if method == HTTP_CONST.METHOD_GET then
    if file:isFile() then
      handleGetFile(httpExchange, file)
    elseif file:isDirectory() then
      handleGetDirectory(httpExchange, file)
    else
      httpHandler.notFound(httpExchange)
    end
  elseif method == HTTP_CONST.METHOD_PUT then
    if request:getBody() then
      file:write(request:getBody()) -- TODO Handle errors
    end
    httpHandler.ok(httpExchange)
  elseif method == HTTP_CONST.METHOD_DELETE then
    if file:isFile() then
      file:delete() -- TODO Check
      httpHandler.ok(httpExchange)
    end
  else
    httpHandler.methodNotAllowed(httpExchange)
  end
end

function httpHandler.webdav(httpExchange)
  local request = httpExchange:getRequest()
  local context = httpExchange:getContext()
  local rootFile = context:getAttribute('rootFile') or File:new('.')
  if not rootFile then
    rootFile = File:new(context:getAttribute('rootPath') or '.')
    context:setAttribute('rootFile', rootFile)
  end
  local method = string.upper(request:getMethod())
  local path = httpExchange:getRequestArguments()
  path = string.gsub(path, '/$', '')
  local file = File:new(rootFile, path)
  if method == HTTP_CONST.METHOD_GET then
    if file:isFile() then
      handleGetFile(httpExchange, file)
    else
      httpHandler.notFound(httpExchange)
    end
  elseif method == HTTP_CONST.METHOD_PUT then
    if request:getBody() then
      file:write(request:getBody()) -- TODO Handle errors
    end
    httpHandler.ok(httpExchange)
  elseif method == HTTP_CONST.METHOD_DELETE then
    if file:isFile() then
      file:delete() -- TODO Check
      httpHandler.ok(httpExchange)
    end
  elseif method == 'PROPFIND' then
    if file:isDirectory() then
      -- "0", "1", or "infinity"
      local uriPath = request:getTargetPath()
      uriPath = uriPath..'/'
      local depth = request:getHeader('Accept') or 'infinity'
      local filenames = file:list()
      local body = '<?xml version="1.0" encoding="utf-8" ?>\n<multistatus xmlns="DAV:">\n'
      for i, filename in ipairs(filenames) do
        local f = File:new(file, filename)
        if f:isDirectory() then
          filename = filename..'/'
        end
        body = body..'<response>\n<href>'..uriPath..filename..'</href>\n'..
            '<propstat>\n<prop>\n<creationdate/>\n<displayname/>\n<getcontentlength/>\n<getcontenttype/>\n<getetag/>\n'..
            '<getlastmodified/>\n<resourcetype/>\n<supportedlock/>\n</prop>\n'..
            '<status>HTTP/1.1 200 OK</status>\n</propstat>\n</response>\n'
      end
      body = body..'</multistatus>\n'
      httpHandler.ok(httpExchange, body, HTTP_CONTENT_TYPES.xml)
    else
      httpHandler.notFound(httpExchange)
    end
  elseif method == 'PROPPATCH' or method == 'MKCOL' or method == 'COPY' or method == 'MOVE' or method == 'LOCK' or method == 'UNLOCK' then
    httpHandler.internalServerError(httpExchange)
  else
    httpHandler.methodNotAllowed(httpExchange)
  end
end

--- Exposes zip content
function httpHandler.zip(httpExchange)
  local request = httpExchange:getRequest()
  local context = httpExchange:getContext()
  local zipFile = context:getAttribute('zipFile')
  --zipFile = ZipFile:new(file)
  if not zipFile then
    httpHandler.internalServerError(httpExchange)
    return
  end
  local path = httpExchange:getRequestArguments()
  local entry = zipFile:getEntry(filename)
  if entry then
    local content = zipFile:getContent(entry)
    response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
    local extension = File.extractExtension(path)
    response:setContentType(HTTP_CONTENT_TYPES[extension] or HTTP_CONTENT_TYPES.bin)
    response:setCacheControl(true)
    response:setContentLength(#content)
    response:setBody(content)
  else
    httpHandler.notFound(httpExchange)
  end
  --zipFile:close()
end

--- Proxies requests
function httpHandler.redirect(httpExchange)
  local request = httpExchange:getRequest()
  local response = httpExchange:getResponse()
  local context = httpExchange:getContext()
  local url = context:getAttribute('url') or ''
  local path = httpExchange:getRequestArguments()
  url = url..path
  logger:debug('redirecting to "'..url..'"')
  local client = http.Client:new({
    url = url,
    method = request:getMethod(),
    headers = request:getHeaders()
  })
  return client:connect():next(function()
    logger:debug('httpHandler.redirect() connected')
    return client:sendReceive()
  end):next(function(subResponse)
    logger:debug('redirect client status code is '..tostring(subResponse:getStatusCode()))
    response:setStatusCode(subResponse:getStatusCode())
    response:setHeaders(subResponse:getHeaders())
    response:setBody(subResponse:getBody())
    client:close()
  end, function(err)
    logger:debug('redirect error: '..tostring(err))
    response:setStatusCode(HTTP_CONST.HTTP_INTERNAL_SERVER_ERROR, 'Internal Server Error')
    response:setBody('<p>Sorry something went wrong on our side.</p>')
    client:close()
  end)
end

local REST_NOT_FOUND = {}

local REST_ANY = '/any'
local REST_METHOD = '/method'

function httpHandler.shiftPath(path)
  return string.match(path, '^([^/]+)/?(.*)$')
end

function httpHandler.restPart(handlers, httpExchange, path)
  local name, remainingPath = httpHandler.shiftPath(path)
  local handler
  if name then
    handler = handlers[REST_ANY]
    if handler then
      if type(handlers.name) == 'string' then
        local value = name
        if type(handlers.value) == 'function' then
          value = handlers.value(httpExchange, name)
        end
        if value == nil then
          return REST_NOT_FOUND
        end
        httpExchange:setAttribute(handlers.name, value)
      end
    elseif handlers[name] then
      handler = handlers[name]
    end
  else
    handler = handlers['']
  end
  if type(handler) == 'table' then
    return httpHandler.restPart(handler, httpExchange, remainingPath)
  elseif type(handler) == 'function' then
    httpExchange:setAttribute('path', remainingPath)
    return handler(httpExchange)
  end
  if path == 'names' then
    local names = {}
    for name in pairs(handlers) do
      table.insert(names, name)
    end
    return names
  end
  return REST_NOT_FOUND
end

--- Groups handlers in a table
function httpHandler.rest(httpExchange)
  local context = httpExchange:getContext()
  local handlers = context:getAttribute('handlers')
  if not handlers then
    httpHandler.internalServerError(httpExchange)
    return
  end
  local attributes = context:getAttribute('attributes')
  if attributes and type(attributes) == 'table' then
    httpExchange:setAttributes(attributes)
  end
  -- if there is a request body with json content type then decode it
  --[[local request = httpExchange:getRequest()
  if request:getBody() and request:getHeader(HTTP_CONST.HEADER_CONTENT_TYPE) == HTTP_CONTENT_TYPES.json then
    local rt = json.decode(request:getBody())
    httpExchange:setAttribute('body', rt)
  end]]
  local path = httpExchange:getRequestArguments()
  local body = httpHandler.restPart(handlers, httpExchange, path)
  if body == nil then
    httpHandler.ok(httpExchange)
  elseif body == REST_NOT_FOUND then
    httpHandler.notFound(httpExchange)
  elseif type(body) == 'string' then
    httpHandler.ok(httpExchange, body, HTTP_CONTENT_TYPES.txt)
  elseif type(body) == 'table' then
    httpHandler.ok(httpExchange, json.encode(body), HTTP_CONTENT_TYPES.json)
  elseif body == false then
    -- response by handler
  else
    httpHandler.internalServerError(httpExchange)
  end
end

--- Exposes a table content
function httpHandler.table(httpExchange)
  local request = httpExchange:getRequest()
  local context = httpExchange:getContext()
  local t = context:getAttribute('table')
  local p = context:getAttribute('path') or ''
  if not t then
    t = {}
    context:setAttribute('table', t)
  end
  local method = string.upper(request:getMethod())
  --local path = httpExchange:getRequest():getTarget()
  local path = httpExchange:getRequestArguments()
  local tp = p..string.gsub(path, '/$', '')
  if logger:isLoggable(logger.FINE) then
    logger:fine('httpHandler.table(), method: "'..method..'", path: "'..tp..'"')
  end
  -- TODO Handle HEAD as a GET without body
  if method == HTTP_CONST.METHOD_GET then
    local value = tables.getPath(t, tp)
    httpHandler.ok(httpExchange, json.encode({
      --success = true,
      --path = path,
      value = value
    }), HTTP_CONTENT_TYPES.json)
  elseif not context:getAttribute('editable') then
    httpHandler.methodNotAllowed(httpExchange)
  elseif method == HTTP_CONST.METHOD_PUT or method == HTTP_CONST.METHOD_POST or method == HTTP_CONST.METHOD_PATCH then
    if logger:isLoggable(logger.FINEST) then
      logger:finest('httpHandler.table(), request body: "'..request:getBody()..'"')
    end
    if request:getBody() then
      local rt = json.decode(request:getBody())
      if type(rt) == 'table' and rt.value then
        if method == HTTP_CONST.METHOD_PUT then
          tables.setPath(t, tp, rt.value)
        elseif method == HTTP_CONST.METHOD_POST then
          local value = tables.getPath(t, tp)
          if type(value) == 'table' then
            tables.setByPath(value, rt.value)
          end
        elseif method == HTTP_CONST.METHOD_PATCH then
          tables.mergePath(t, tp, rt.value)
        end
      end
    end
    httpHandler.ok(httpExchange)
  elseif method == HTTP_CONST.METHOD_DELETE then
    tables.removePath(t, tp)
    httpHandler.ok(httpExchange)
  else
    httpHandler.methodNotAllowed(httpExchange)
  end
  if logger:isLoggable(logger.FINE) then
    logger:fine('httpHandler.table(), status: '..tostring(httpExchange:getResponse():getStatusCode()))
  end
end

return httpHandler
