--- Provide a simple HTTP handler for Lua tables.
-- This handler allows to access and maintian a Lua table.
-- Exposes a table content throught HTTP REST APIs.
-- @module jls.net.http.handler.TableHttpHandler
-- @pragma nostrip

local logger = require('jls.lang.logger')
local json = require('jls.util.json')
local tables = require('jls.util.tables')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local HttpExchange = require('jls.net.http.HttpExchange')

--- A TableHttpHandler class.
-- @type TableHttpHandler
return require('jls.lang.class').create('jls.net.http.HttpHandler', function(tableHttpHandler)

  --- Creates a Lua table @{HttpHandler}.
  -- @tparam table table the table.
  -- @tparam[opt] string path the table base path.
  -- @tparam[opt] boolean editable true to indicate that the table can be modified.
  function tableHttpHandler:initialize(table, path, editable)
    self.table = table or {}
    self.path = path or ''
    self.editable = editable == true
  end

  function tableHttpHandler:handle(httpExchange)
    local method = httpExchange:getRequestMethod()
    local path = httpExchange:getRequestPath()
    local tp = self.path..string.gsub(path, '/$', '')
    if logger:isLoggable(logger.FINE) then
      logger:fine('httpHandler.table(), method: "'..method..'", path: "'..tp..'"')
    end
    if method == HTTP_CONST.METHOD_GET then
      local value = tables.getPath(self.table, tp)
      HttpExchange.ok(httpExchange, json.encode({
        --success = true,
        --path = path,
        value = value
      }), HttpExchange.CONTENT_TYPES.json)
    elseif not self.editable then
      HttpExchange.methodNotAllowed(httpExchange)
    elseif method == HTTP_CONST.METHOD_PUT or method == HTTP_CONST.METHOD_POST or method == HTTP_CONST.METHOD_PATCH then
      local request = httpExchange:getRequest()
      return httpExchange:onRequestBody(true):next(function()
        if logger:isLoggable(logger.FINEST) then
          logger:finest('httpHandler.table(), request body: "'..request:getBody()..'"')
        end
        if request:getBodyLength() > 0 then
          local rt = json.decode(request:getBody())
          if type(rt) == 'table' and rt.value then
            if method == HTTP_CONST.METHOD_PUT then
              tables.setPath(self.table, tp, rt.value)
            elseif method == HTTP_CONST.METHOD_POST then
              local value = tables.getPath(self.table, tp)
              if type(value) == 'table' then
                tables.setByPath(value, rt.value)
              end
            elseif method == HTTP_CONST.METHOD_PATCH then
              tables.mergePath(self.table, tp, rt.value)
            end
          end
        end
        HttpExchange.ok(httpExchange)
      end)
    elseif method == HTTP_CONST.METHOD_DELETE then
      tables.removePath(self.table, tp)
      HttpExchange.ok(httpExchange)
    else
      HttpExchange.methodNotAllowed(httpExchange)
    end
    if logger:isLoggable(logger.FINE) then
      logger:fine('httpHandler.table(), status: '..tostring(httpExchange:getResponse():getStatusCode()))
    end
  end

end)
