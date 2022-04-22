--- Provide a simple HTTP handler for files.
-- @module jls.net.http.handler.FileHttpHandler
-- @pragma nostrip

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local StringBuffer = require('jls.lang.StringBuffer')
local Path = require('jls.io.Path')
local File = require('jls.io.File')
local FileStreamHandler = require('jls.io.streams.FileStreamHandler')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local HttpExchange = require('jls.net.http.HttpExchange')
local Url = require('jls.net.Url')
local json = require('jls.util.json')

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
  var target = e.target;
  var filename;
  do {
    filename = target.getAttribute('href');
    target = target.previousElementSibling;
  } while ((filename === '#') && target);
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

local function getFileMetadata(file)
  return {
    isDir = file:isDirectory(),
    size = file:length(),
    time = file:lastModified(),
  }
end

local FS = {
  getFileMetadata = function(file)
    if file:exists() then
      return getFileMetadata(file)
    end
  end,
  listFileMetadata = function(dir)
    local files = {}
    for _, file in ipairs(dir:listFiles()) do
      local name = file:getName()
      if string.find(name, '^[^%.]') then
        local md = getFileMetadata(file)
        md.name = name
        table.insert(files, md)
      end
    end
    return files
  end,
  createDirectory = function(file)
    return file:mkdir()
  end,
  copyFile = function(file, destFile)
    return file:copyTo(destFile)
  end,
  renameFile = function(file, destFile)
    return file:renameTo(destFile)
  end,
  deleteFile = function(file, recursive)
    if recursive then
      return file:deleteRecursive()
    end
    return file:delete()
  end,
  setFileStreamHandler = function(httpExchange, file, sh, md, offset, length)
    FileStreamHandler.read(file, sh, offset, length)
  end,
  getFileStreamHandler = function(httpExchange, file)
    return FileStreamHandler:new(file, true)
  end,
}

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
    self.fs = FS
    self.cacheControl = 86400 -- one day
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

  function fileHttpHandler:getCacheControl()
    return self.cacheControl
  end

  function fileHttpHandler:setCacheControl(cacheControl)
    self.cacheControl = cacheControl
    return self
  end

  function fileHttpHandler:getContentType(file)
    return FileHttpHandler.guessContentType(file)
  end

  function fileHttpHandler:getFileSystem()
    return self.fs
  end

  function fileHttpHandler:setFileSystem(fs)
    self.fs = fs or FS
    return self
  end

  function fileHttpHandler:appendFileHtmlBody(buffer, file)
    buffer:append('<a href="', Url.encodeURIComponent(file.name))
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
  end

  function fileHttpHandler:appendDirectoryHtmlBody(buffer, files)
    for _, file in ipairs(files) do
      self:appendFileHtmlBody(buffer, file)
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
    return buffer
  end

  function fileHttpHandler:handleGetDirectory(httpExchange, dir, showParent)
    local response = httpExchange:getResponse()
    local files = self.fs.listFileMetadata(dir)
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
        local path = self:getPath(httpExchange)
        if path ~= '' then
          buffer:append('<a href=".." class="dir">..</a><br/>\n')
        end
      end
      self:appendDirectoryHtmlBody(buffer, files)
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

  function fileHttpHandler:handleGetFile(httpExchange, file, md)
    local response = httpExchange:getResponse()
    response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
    response:setContentType(self:getContentType(file))
    response:setLastModified(md.time)
    response:setCacheControl(self.cacheControl)
    response:setContentLength(md.size)
    response:setHeader('Accept-Ranges', 'bytes')
    if httpExchange:getRequestMethod() == HTTP_CONST.METHOD_GET then
      local request = httpExchange:getRequest()
      local ifModifiedSince = request:getIfModifiedSince()
      if ifModifiedSince and md.time and md.time <= ifModifiedSince then
        response:setStatusCode(HTTP_CONST.HTTP_NOT_MODIFIED, 'Not modified')
        return
      end
      local range = request:getHeader('Range')
      local offset, length
      if range then
        -- only support a single range
        local first, last = string.match(range, '^bytes=(%d*)%-(%d*)%s*$')
        first = first and tonumber(first)
        last = last and tonumber(last)
        if first and first < md.size or last and last < md.size then
          offset = first or (md.size - last)
          if first and last and first <= last then
            length = last - first + 1
          else
            length = md.size - offset
          end
        end
      end
      if offset and length then
        response:setStatusCode(HTTP_CONST.HTTP_PARTIAL_CONTENT, 'Partial')
        response:setContentLength(length)
        local contentRange = 'bytes '..tostring(offset)..'-'..tostring(offset + length - 1)..'/'..tostring(md.size)
        if logger:isLoggable(logger.FINE) then
          logger:fine('Content-Range: '..contentRange..', from Range: '..range)
        end
        response:setHeader('Content-Range', contentRange)
      end
      response:onWriteBodyStreamHandler(function()
        local sh = response:getBodyStreamHandler()
        self.fs.setFileStreamHandler(httpExchange, file, sh, md, offset, length)
      end)
    end
  end

  function fileHttpHandler:receiveFile(httpExchange, file)
    httpExchange:getRequest():setBodyStreamHandler(self.fs.getFileStreamHandler(httpExchange, file))
  end

  function fileHttpHandler:handleGetHeadFile(httpExchange, file)
    local md = self.fs.getFileMetadata(file)
    if md then
      if md.isDir and self.allowList then
        self:handleGetDirectory(httpExchange, file, true)
      else
        self:handleGetFile(httpExchange, file, md)
      end
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
      if self.allowUpdate or not file:exists() then
        if isDirectoryPath then
          self.fs.createDirectory(file) -- TODO Handle errors
        else
          self:receiveFile(httpExchange, file)
        end
        HttpExchange.ok(httpExchange)
      else
        HttpExchange.forbidden(httpExchange)
      end
    elseif method == HTTP_CONST.METHOD_DELETE and self.allowDelete then
      self.fs.deleteFile(file, self.allowDeleteRecursive) -- TODO Handle errors
      HttpExchange.ok(httpExchange)
    elseif method == 'MOVE' and self.allowCreate and self.allowDelete then
      local request = httpExchange:getRequest()
      local destination = request:getHeader('destination')
      if string.find(destination, '://') then
        destination = Url:new(destination):getPath()
      end
      destination = Url.decodePercent(destination)
      local destPath = httpExchange:getContext():getArguments(destination)
      if destPath then
        local destFile = self:findFile(destPath)
        self.fs.renameFile(file, destFile)
        HttpExchange.ok(httpExchange, HTTP_CONST.HTTP_CREATED, 'Moved')
      else
        HttpExchange.badRequest(httpExchange)
      end
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
    filePath = Url.decodePercent(filePath)
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
    elseif path then
      extension = path:getExtension()
    else
      extension = ''
    end
    return HttpExchange.CONTENT_TYPES[extension] or def or HttpExchange.CONTENT_TYPES.bin
  end

end)
