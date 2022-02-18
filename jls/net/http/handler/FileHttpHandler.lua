--- Provide a simple HTTP handler for files.
-- @module jls.net.http.handler.FileHttpHandler
-- @pragma nostrip

local logger = require('jls.lang.logger')
local json = require('jls.util.json')
local Path = require('jls.io.Path')
local File = require('jls.io.File')
local Promise = require('jls.lang.Promise')
local FileStreamHandler = require('jls.io.streams.FileStreamHandler')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local StringBuffer = require('jls.lang.StringBuffer')
local HttpExchange = require('jls.net.http.HttpExchange')
local URL = require('jls.net.URL')

local DIRECTORY_STYLE = [[<style>
a {
  text-decoration: none;
  color: inherit;
}
a:hover {
  text-decoration: underline;
}
a.dir {
  font-weight: bold;
}
</style>
]]

local DELETE_SCRIPT = [[
<script>
function delFile(e) {
  var filename = e.target.previousElementSibling.getAttribute('href');
  if (window.confirm('Delete file "' + decodeURIComponent(filename) + '"?')) {
    fetch(filename, {
      method: "DELETE"
    }).then(function() {
      window.location.reload();
    });
  }
}
</script>
]]

local PUT_SCRIPT = [[
<input type="file" multiple onchange="putFiles(this.files)" />
<script>
function stopEvent(e) {
  e.preventDefault();
  e.stopPropagation();
} 
function putFiles(files) {
  files = Array.prototype.slice.call(files);
  Promise.all(files.map(function(file) {
    return fetch(file.name, {
      method: "PUT",
      body: file
    });
  })).then(function() {
    window.location.reload();
  });
}
if (window.File && window.FileReader && window.FileList && window.Blob) {
  document.addEventListener("dragover", stopEvent);
  document.addEventListener("drop", function(e) {
    stopEvent(e);
    putFiles(e.dataTransfer.files);
  });
  document.querySelector("input[type=file]").style.display = "none";
}
</script>
]]

--- A FileHttpHandler class.
-- @type FileHttpHandler
return require('jls.lang.class').create('jls.net.http.HttpHandler', function(fileHttpHandler, _, FileHttpHandler)

  --- Creates a file @{HttpHandler}.
  -- @tparam File rootFile the root File
  -- @tparam[opt] string permissions a string containing the granted permissions, 'rwxlcud' default is 'r'
  -- @tparam[opt] string indexFilename the name of the file to use in case of GET request on a directory
  -- @function FileHttpHandler:new
  function fileHttpHandler:initialize(rootFile, permissions, indexFilename)
    self.rootFile = File.asFile(rootFile)
    if indexFilename then
      if type(indexFilename) == 'string' and indexFilename ~= '' then
        self.defaultFile = indexFilename
      end
    else
      self.defaultFile = 'index.html'
    end
    if type(permissions) ~= 'string' then
      permissions = 'r'
    end
    self.allowRead = not not string.match(permissions, 'r')
    self.allowList = not not string.match(permissions, '[xl]')
    self.allowUpdate = not not string.match(permissions, '[wu]')
    self.allowCreate = not not string.match(permissions, '[wc]')
    self.allowDelete = not not string.match(permissions, '[wd]')
    self.allowDeleteRecursive = not not string.match(permissions, '[RD]')
    if logger:isLoggable(logger.FINER) then
      logger:finer('fileHttpHandler permissions is "'..permissions..'"')
      for k, v in pairs(self) do
        logger:finest('  '..tostring(k)..': "'..tostring(v)..'"')
      end
    end
  end

  function fileHttpHandler:getContentType(file)
    return FileHttpHandler.guessContentType(file)
  end

  function fileHttpHandler:listFiles(dir)
    local files = {}
    for _, file in ipairs(dir:listFiles()) do
      local name = file:getName()
      table.insert(files, {
        name = name,
        isDir = file:isDirectory(),
        size = file:length(),
        --time = file:lastModified(),
      })
    end
    return files
  end

  function fileHttpHandler:handleGetDirectory(httpExchange, dir, showParent)
    local response = httpExchange:getResponse()
    local files = self:listFiles(dir)
    local body = ''
    local request = httpExchange:getRequest()
    if request:hasHeaderValue(HTTP_CONST.HEADER_ACCEPT, HttpExchange.CONTENT_TYPES.json) then
      body = json.encode(files)
      response:setContentType(HttpExchange.CONTENT_TYPES.json)
    else
      local buffer = StringBuffer:new()
      buffer:append('<html><head><meta charset="UTF-8">\n')
      buffer:append(DIRECTORY_STYLE)
      buffer:append('</head><body>\n')
      if showParent then
        buffer:append('<a href=".." class="dir">..</a><br/>\n')
      end
      for _, file in ipairs(files) do
        buffer:append('<a href="', URL.encodeURIComponent(file.name))
        if file.isDir then
          buffer:append('/"')
        else
          buffer:append('"')
          if file.size then
            buffer:append(' title="', file.size, ' bytes"')
          end
        end
        if file.isDir then
          buffer:append(' class="dir"')
        end
        buffer:append('>', file.name, '</a>\n')
        if self.allowDelete and not file.isDir then
          buffer:append('<a href="#" title="delete" onclick="delFile(event)">&#x2715;</a>\n')
        end
        buffer:append('<br/>\n')
      end
      if self.allowCreate then
        buffer:append(PUT_SCRIPT)
      end
      if self.allowDelete then
        buffer:append(DELETE_SCRIPT)
      end
      buffer:append('</body></html>\n')
      body = buffer:toString()
      response:setContentType(HttpExchange.CONTENT_TYPES.html)
    end
    response:setCacheControl(false)
    response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
    response:setBody(body)
  end

  function fileHttpHandler:findFile(path, readOnly)
    local file = File:new(self.rootFile, path)
    if readOnly and file:isDirectory() and not self.allowList and self.defaultFile then
      file = File:new(file, self.defaultFile)
    end
    return file
  end

  function fileHttpHandler:handleGetFile(httpExchange, file)
    local response = httpExchange:getResponse()
    response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
    response:setContentType(self:getContentType(file))
    response:setCacheControl(false)
    response:setContentLength(file:length())
    if httpExchange:getRequestMethod() == HTTP_CONST.METHOD_GET then
      self:sendFile(httpExchange, file)
    end
  end

  function fileHttpHandler:receiveFile(httpExchange, file)
    httpExchange:getRequest():setBodyStreamHandler(FileStreamHandler:new(file, true))
  end

  function fileHttpHandler:sendFile(httpExchange, file)
    local response = httpExchange:getResponse()
    response:onWriteBodyStreamHandler(function()
      FileStreamHandler.readAll(file, response:getBodyStreamHandler())
    end)
  end

  function fileHttpHandler:handleGetHeadFile(httpExchange, file)
    if file:isFile() then
      self:handleGetFile(httpExchange, file)
    elseif file:isDirectory() and self.allowList then
      self:handleGetDirectory(httpExchange, file, true)
    else
      HttpExchange.notFound(httpExchange)
    end
  end

  function fileHttpHandler:prepareFile(httpExchange, file)
    return Promise.resolve()
  end

  function fileHttpHandler:handleFile(httpExchange, file, isDirectoryPath)
    local method = httpExchange:getRequestMethod()
    -- TODO Handle PATCH, MOVE
    if method == HTTP_CONST.METHOD_GET or method == HTTP_CONST.METHOD_HEAD then
      return self:prepareFile(httpExchange, file):next(function()
        self:handleGetHeadFile(httpExchange, file)
      end, function()
        HttpExchange.notFound(httpExchange)
      end)
    elseif method == HTTP_CONST.METHOD_POST and self.allowUpdate then
      if self.allowCreate or file:isFile() then
        self:receiveFile(httpExchange, file)
        HttpExchange.ok(httpExchange)
      else
        HttpExchange.forbidden(httpExchange)
      end
    elseif method == HTTP_CONST.METHOD_PUT and self.allowCreate then
      if isDirectoryPath then
        file:mkdir() -- TODO Handle errors
      else
        self:receiveFile(httpExchange, file)
      end
      HttpExchange.ok(httpExchange)
    elseif method == HTTP_CONST.METHOD_DELETE and self.allowDelete then
      if self.allowDeleteRecursive then
        file:deleteRecursive() -- TODO Handle errors
      else
        file:delete() -- TODO Handle errors
      end
      HttpExchange.ok(httpExchange)
    else
      HttpExchange.methodNotAllowed(httpExchange)
    end
  end

  function fileHttpHandler:getPath(httpExchange)
    return httpExchange:getRequestPath()
  end

  function fileHttpHandler:isValidPath(httpExchange, path)
  end

  function fileHttpHandler:handle(httpExchange)
    local method = httpExchange:getRequestMethod()
    local path = self:getPath(httpExchange)
    local isDirectoryPath = string.sub(path, -1) == '/'
    local filePath = isDirectoryPath and string.sub(path, 1, -2) or path
    filePath = URL.decodePercent(filePath)
    if not HttpExchange.isValidSubPath(path) then
      HttpExchange.forbidden(httpExchange)
      return
    end
    local readOnly = method == HTTP_CONST.METHOD_GET or method == HTTP_CONST.METHOD_HEAD
    local file = self:findFile(filePath, readOnly)
    if logger:isLoggable(logger.FINE) then
      logger:fine('fileHttpHandler method is "'..method..'" file is "'..file:getPath()..'"')
    end
    return self:handleFile(httpExchange, file, isDirectoryPath)
  end

  function FileHttpHandler.guessContentType(path, def)
    local extension
    if type(path) == 'string' then
      extension = Path.extractExtension(path)
    else
      extension = path:getExtension()
    end
    return HttpExchange.CONTENT_TYPES[extension] or def or HttpExchange.CONTENT_TYPES.bin
  end

end)
