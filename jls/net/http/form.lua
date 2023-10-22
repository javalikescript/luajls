local logger = require('jls.lang.logger')
local Date = require('jls.util.Date')
local strings = require('jls.util.strings')
local StringBuffer = require('jls.lang.StringBuffer')
local HttpMessage = require('jls.net.http.HttpMessage')

local form = {}

-- see https://en.wikipedia.org/wiki/POST_%28HTTP%29
-- and https://tools.ietf.org/html/rfc2388
-- and https://tools.ietf.org/html/rfc1867

function form.getFormDataName(message)
  local rawValue = message:getHeader(HttpMessage.CONST.HEADER_CONTENT_DISPOSITION)
  local value, params = HttpMessage.parseHeaderValueAsTable(rawValue)
  if value == 'form-data' then
    for key, param in pairs(params) do
      local v = string.match(param, '^"(.*)"$')
      if v then
        params[key] = v
      end
    end
    return params['name'], params
  end
end

function form.setFormDataName(message, name, filename, contentType)
  local value = 'form-data; name="'..name..'"'
  if filename then
    value = value..'; filename="'..filename..'"'
  end
  message:setHeader(HttpMessage.CONST.HEADER_CONTENT_DISPOSITION, value)
  if contentType then
    message:setHeader(HttpMessage.CONST.HEADER_CONTENT_TYPE, contentType)
  end
end

function form.createFormRequest(request, messages)
  local boundary = '---------------------------'..tostring(Date.now())
  request:setHeader(HttpMessage.CONST.HEADER_CONTENT_TYPE, 'multipart/form-data; boundary='..boundary)
  local buffer = StringBuffer:new()
  for _, message in ipairs(messages) do
    buffer:append('--', boundary, '\r\n', message:getRawHeaders(), '\r\n', message:getBody(), '\r\n')
  end
  buffer:append('--', boundary, '--\r\n')
  local body = buffer:toString()
  request:setBody(body)
  request:setContentLength(#body)
end

function form.parseFormData(request, boundary)
  if logger:isLoggable(logger.FINE) then
    logger:fine('boundary is "%s"', boundary)
  end
  local body = request:getBody()
  if logger:isLoggable(logger.FINEST) then
    logger:finest('body is "%s"', body)
  end
  local messages = {}
  local contents = strings.split(body, '--'..boundary, true)
  if contents[#contents] == '--\r\n' then
    table.remove(contents)
    logger:fine('contents count is %s', #contents)
    for _, content in ipairs(contents) do
      logger:finest('processing content "%s"', content)
      local message = HttpMessage:new()
      local index = string.find(content, '\r\n\r\n', 1, true)
      if index then
        local rawHeader = string.sub(content, 1, index - 1)
        local rawContent = string.sub(content, index + 4, -3)
        local lines = strings.split(rawHeader, '\r\n')
        for _, line in ipairs(lines) do
          message:parseHeaderLine(line)
        end
        message:setBody(rawContent)
        table.insert(messages, message)
        logger:finest('content body "%s"', rawContent)
      end
    end
  end
  return messages
end

function form.parseFormUrlEncoded(request)
  -- name=test&password=test
  local body = request:getBody()
  logger:finest('body is "%s"', body)
  local map = {}
  for _, keyValue in ipairs(strings.split(body, '&', true)) do
    local key, value = string.match(keyValue, '([^=]+)=(.+)')
    if key then
      map[key] = value
    end
  end
  return map
end

function form.parseFormRequest(request)
  local contentTypeRawValue = request:getHeader(HttpMessage.CONST.HEADER_CONTENT_TYPE)
  if not contentTypeRawValue then
    return nil, 'Missing content type'
  end
  local contentType, params = HttpMessage.parseHeaderValueAsTable(contentTypeRawValue)
  if string.lower(contentType) == 'application/x-www-form-urlencoded' then
    return form.parseFormUrlEncoded(request)
  elseif string.lower(contentType) == 'multipart/form-data' then
    return form.parseFormData(request, params['boundary'])
  end
  return nil, 'Unsupported content type ('..tostring(contentType)..')'
end

return form
