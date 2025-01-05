--- Provide a simple router HTTP handler.
-- @module jls.net.http.handler.RouterHttpHandler
-- @pragma nostrip

local class = require('jls.lang.class')
local logger = require('jls.lang.logger'):get(...)
local Promise = require('jls.lang.Promise')
local Exception = require('jls.lang.Exception')
local HttpHandler = require('jls.net.http.HttpHandler')
local HttpMessage = require('jls.net.http.HttpMessage')
local HttpExchange = require('jls.net.http.HttpExchange')
local json = require('jls.util.json')
local strings = require('jls.util.strings')
local List = require('jls.util.List')
local xml = require("jls.util.xml")

local ROUTER_DONE = {}
local ROUTER_NOT_FOUND = {}
local ROUTER_ANY = '{*}'
local ROUTER_ALL = '{+}'
local ROUTER_ALIAS = {accept = 'header:accept', ['content-type'] = 'header:content-type'}
local ROUTER_FILTERS = {method = true, query = true, order = true}
local ROUTER_GROUPS = {header = 'header', [''] = 'header', parameter = 'param', param = 'param', q = 'param'}

--[[
see https://expressjs.com/en/starter/basic-routing.html
"Routing refers to determining how an application responds to a client request to a particular endpoint,
which is a URI (or path) and a specific HTTP request method (GET, POST, and so on)."
]]

-- the characters : / ? # [ ] @ are reserved for use as delimiters of the generic URI components

local function addAt(map, key, value)
  local values = map[key]
  if values then
    table.insert(values, value)
  else
    values = {value}
    map[key] = values
  end
  return values
end

local BaseHttpHandler = class.create(HttpHandler, function(baseHttpHandler)

  function baseHttpHandler:initialize(fn)
    self.fn = fn or class.emptyFunction
  end

  function baseHttpHandler:handle(exchange, capture)
    return self.fn(exchange, capture)
  end

end)

local RouteHttpHandler = class.create(HttpHandler, function(routeHttpHandler)

  function routeHttpHandler:initialize(infos, all)
    self.infos = infos or {}
    self.all = all
  end

  -- see https://www.w3.org/TR/2018/REC-selectors-3-20181106/#attribute-substrings
  -- '^=' begins with, '$=' ends with, '*=' contains, '~=' contains a whitespace-separated
  -- '|=' in list, '/=' match pattern, '+=' capture
  local function acceptValue(exchange, filter, value)
    if filter.op == '' then
      return value == filter.value
    elseif filter.op == '*' then
      return string.find(value, filter.value, 1, true)
    elseif filter.op == '/' then
      return string.find(value, filter.value)
    elseif filter.op == '^' then
      return strings.startsWith(value, filter.value)
    elseif filter.op == '$' then
      return strings.endsWith(value, filter.value)
    elseif filter.op == '|' then
      return filter.values[value] ~= nil
    elseif filter.op == '+' then
      return true
    end
    return false
  end

  local function acceptValues(exchange, filterMap, valueMap)
    for name, filter in pairs(filterMap) do
      if not acceptValue(exchange, filter, valueMap[name]) then
        return false
      end
    end
    return true
  end

  local function captureValue(exchange, filter, value)
    if filter.op == '+' then
      exchange:setAttribute(filter.value, value)
    end
  end

  local function captureValues(exchange, filterMap, valueMap)
    for name, filter in pairs(filterMap) do
      captureValue(exchange, filter, valueMap[name])
    end
  end

  local function acceptRequest(exchange, info)
    if info.method and not acceptValue(exchange, info.method, exchange:getRequest():getMethod()) then
      return false
    end
    if info.query and not acceptValue(exchange, info.query, exchange:getRequest():getTargetQuery()) then
      return false
    end
    if info.header and not acceptValues(exchange, info.header, exchange:getRequest():getHeadersTable()) then
      return false
    end
    if info.param and not acceptValues(exchange, info.param, exchange:getRequest():getSearchParams()) then
      return false
    end
    -- the request is accepted then capture the values
    if info.method then
      captureValue(exchange, info.method, exchange:getRequest():getMethod())
    end
    if info.query then
      captureValue(exchange, info.query, exchange:getRequest():getTargetQuery())
    end
    if info.header then
      captureValues(exchange, info.header, exchange:getRequest():getHeadersTable())
    end
    if info.param then
      captureValues(exchange, info.param, exchange:getRequest():getSearchParams())
    end
    return true
  end

  function routeHttpHandler:handle(exchange, capture)
    for _, info in ipairs(self.infos) do
      if acceptRequest(exchange, info) then
        local values, count = {}, 0
        if info.args then
          for index, name in ipairs(info.args) do
            local value = exchange:getAttribute(name)
            values[index] = value
          end
          count = #info.args
        end
        if self.all then
          local result = info.fn(exchange, capture, table.unpack(values, 1, count))
          if result ~= nil then
            return result
          end
        else
          return info.fn(exchange, table.unpack(values, 1, count))
        end
      else
        logger:finer('route request "%s" not accepted', exchange:getRequest():getTarget())
      end
    end
    if not self.all then
      return ROUTER_NOT_FOUND
    end
  end

end)

local function compareByOrder(a, b)
  return a.order > b.order
end

local function prepareHandlers(handlers)
  local preparedHandlers = {}
  local infosByPath = {}
  for fullPath, value in pairs(handlers) do
    local path, info
    path = fullPath
    if type(value) == 'function' then -- TODO accept HttpHandler instance
      info = {}
      info.fn = value
      local order = 0
      local p, q = string.match(path, '^([^%?]*)%?(.+)$')
      if p then
        path = p
        for part in strings.parts(q, '&', true) do
          local filter
          local filterKey, filterValue = string.match(part, '^([^=]+)=(.*)$')
          local filterOp = string.sub(filterKey, -1)
          if string.find('*^$|/+', filterOp, 1, true) then
            filterKey = string.sub(filterKey, 1, -2)
          else
            filterOp = ''
          end
          filterKey = strings.trim(filterKey)
          filterValue = strings.trim(filterValue)
          filter = {
            op = filterOp,
            value = filterValue
          }
          if filterOp == '|' then
            filter.values = List.asSet(strings.split(filterValue, filterOp, true))
          end
          if ROUTER_ALIAS[filterKey] then
            filterKey = ROUTER_ALIAS[filterKey]
          end
          local group, subKey = string.match(filterKey, '^([^:]*):(.+)$')
          if group and ROUTER_GROUPS[group] then
            group = ROUTER_GROUPS[group]
            local values = info[group]
            if not values then
              values = {}
              info[group] = values
            end
            if group == 'header' then
              subKey = string.lower(subKey)
            end
            values[subKey] = filter
            order = order + 1
          elseif ROUTER_FILTERS[filterKey] then
            if filterKey == 'method' and filterOp == '' then
              filter.op = '|'
              filter.values = List.asSet(strings.split(filterValue, ',', true))
            elseif filterKey == 'order' and filterOp == '' then
              filter = tonumber(filterValue)
            end
            info[filterKey] = filter
            order = order + 1
          else
            error('invalid filter "'..q..'" at "'..filterKey..' '..filterOp..'= '..filterValue..'"')
          end
        end
        info.args = {} -- to force processing query filters
      end
      p, q = string.match(path, '^(.*)%(([%a_][%a%d_,%s]*)%)$')
      if p then
        path = p
        -- TODO indicate that a parameter is mandatory or optional
        info.args = strings.split(q, '%s*,%s*')
      end
      if not info.order then
        info.order = order
      end
    end
    local name = string.match(path, '^{([%a_][%a%d_]*)}$')
    if name then
      path = ROUTER_ANY
      addAt(infosByPath, ROUTER_ALL, {
        fn = function(exchange, capture)
          exchange:setAttribute(name, capture)
        end,
        order = 0
      })
    end
    if info then
      addAt(infosByPath, path, info)
    elseif type(value) == 'table' then
      preparedHandlers[path] = prepareHandlers(value)
    else
      preparedHandlers[path] = value
    end
  end
  for path, infos in pairs(infosByPath) do
    if #infos == 1 and not infos[1].args then
      preparedHandlers[path] = BaseHttpHandler:new(infos[1].fn)
    else
      table.sort(infos, compareByOrder)
      logger:finer('Router path "%s" prepared with handlers %T', path, infos)
      preparedHandlers[path] = RouteHttpHandler:new(infos, path == ROUTER_ALL)
    end
  end
  return preparedHandlers
end

local function shiftPath(path)
  return string.match(path, '^([^/]+)/?(.*)$')
end

local function routerPart(handlers, exchange, path)
  local name, remainingPath = shiftPath(path)
  local handler
  if name then
    handler = handlers[name]
    if not handler then
      handler = handlers[ROUTER_ANY]
    end
    local allHandler = handlers[ROUTER_ALL]
    if allHandler and HttpHandler:isInstance(allHandler) then
      local r = allHandler:handle(exchange, name)
      if r ~= nil then
        return r
      end
    end
  else
    handler = handlers['']
  end
  if type(handler) ~= 'table' then
    return ROUTER_NOT_FOUND
  end
  if HttpHandler:isInstance(handler) then
    exchange:setAttribute('path', remainingPath)
    return handler:handle(exchange)
  end
  return routerPart(handler, exchange, remainingPath)
end

local function processRestResponse(exchange, result)
  if result == nil then
    HttpExchange.ok(exchange)
  elseif result == ROUTER_DONE or result == false then
    -- response by handler
  elseif result == ROUTER_NOT_FOUND then
    HttpExchange.notFound(exchange)
  else
    local contentType = exchange:getResponse():getContentType()
    if contentType == HttpExchange.CONTENT_TYPES.json then
      HttpExchange.ok(exchange, json.stringify(result))
    elseif type(result) == 'string' then
      HttpExchange.ok(exchange, result, HttpExchange.CONTENT_TYPES.txt)
    elseif type(result) == 'table' then
      if contentType == HttpExchange.CONTENT_TYPES.xml then
        HttpExchange.ok(exchange, xml.encode(result))
      else
        HttpExchange.ok(exchange, json.stringify(result), HttpExchange.CONTENT_TYPES.json)
      end
    else
      HttpExchange.internalServerError(exchange)
    end
  end
end

--- A RouterHttpHandler class.
-- @type RouterHttpHandler
return class.create(HttpHandler, function(routerHttpHandler, _, RouterHttpHandler)

  --- Creates a Router @{HttpHandler}.
  -- @tparam table handlers the Router path handlers as a Lua table.
  -- @tparam[opt] table attributes exchange attributes.
  -- @tparam[opt] boolean noBody true to indicate the request body should not be consumed.
  function routerHttpHandler:initialize(handlers, attributes, noBody)
    self.handlers = prepareHandlers(handlers or {})
    if type(attributes) == 'table' then
      self.attributes = attributes
    end
    self.consumeBody = noBody ~= true
  end

  function routerHttpHandler:handleNow(exchange)
    local path = exchange:getRequestPath()
    local status, result = Exception.pcall(routerPart, self.handlers, exchange, path)
    if status then
      if Promise.isPromise(result) then
        return Promise.resolve(result):next(function(r)
          processRestResponse(exchange, r)
          return true
        end)
      end
      processRestResponse(exchange, result)
    else
      logger:warn('Router handler error: %s', result)
      HttpExchange.internalServerError(exchange)
    end
  end

  function routerHttpHandler:handle(exchange)
    if self.attributes then
      exchange:setAttributes(self.attributes)
    end
    if self.consumeBody then
      local request = exchange:getRequest()
      local length = request:getContentLength()
      if length and length > 0 then
        request:bufferBody()
        return request:consume():next(function()
          local contentType = request:getContentType()
          local method = request:getMethod()
          if method == HttpMessage.CONST.METHOD_POST or method == HttpMessage.CONST.METHOD_PUT then
            if contentType == HttpExchange.CONTENT_TYPES.json then
              local requestJson = json.decode(request:getBody()) -- TODO Handle parsing errors
              exchange:setAttribute('requestJson', requestJson)
            elseif contentType == HttpExchange.CONTENT_TYPES.xml then
              local requestXml = xml.decode(request:getBody()) -- TODO Handle parsing errors
              exchange:setAttribute('requestXml', requestXml)
            end
          end

          return self:handleNow(exchange)
        end)
      end
    end
    return self:handleNow(exchange)
  end

  function RouterHttpHandler.replyJson(exchange, t)
    local response = exchange:getResponse()
    response:setStatusCode(HttpMessage.CONST.HTTP_OK, 'OK')
    response:setContentType(HttpExchange.CONTENT_TYPES.json)
    response:setBody(json.stringify(t))
  end

  RouterHttpHandler.routerPart = routerPart
  RouterHttpHandler.shiftPath = shiftPath

  RouterHttpHandler.ROUTER_NOT_FOUND = ROUTER_NOT_FOUND
  RouterHttpHandler.ROUTER_DONE = ROUTER_DONE
  RouterHttpHandler.ROUTER_ANY = ROUTER_ANY
  RouterHttpHandler.ROUTER_ALL = ROUTER_ALL

  -- Deprecated, to remove
  RouterHttpHandler.restPart = routerPart
  RouterHttpHandler.REST_NOT_FOUND = ROUTER_NOT_FOUND
  RouterHttpHandler.REST_DONE = ROUTER_DONE
  RouterHttpHandler.REST_ANY = ROUTER_ANY
  RouterHttpHandler.REST_ALL = ROUTER_ALL

end)
