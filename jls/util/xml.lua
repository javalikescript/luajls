--- Provide XML codec.
-- The XML is represented as a table.
-- @module jls.util.xml

local XmlParser = require('XmlParser') -- xml2lua parser
local class = require('jls.lang.class')
local StringBuffer = require('jls.lang.StringBuffer')
--local TableList = require('jls.util.TableList')

local function getLocalName(qName)
  local prefix, localName = string.match(qName, '^([^:]+):.+$')
  if prefix then
    return localName, prefix
  end
  return qName
end

local function composeQName(prefix, localName)
  if prefix then
    return prefix..':'..localName
  end
  return localName
end

local ESCAPED_ENTITIES = {
  amp = '&',
  apos = '\'',
  gt = '>',
  quot = '"',
  lt = '<',
}

local ESCAPED_CHARS = {}
for e, c in pairs(ESCAPED_ENTITIES) do
  ESCAPED_CHARS[c] = '&'..e..';'
end

local function unescape(s)
  s = string.gsub(s, '&(%a+);', function(e)
    return ESCAPED_ENTITIES[e] or ''
  end)
  s = string.gsub(s, '&#(x?)(%x+);', function(x, v)
    local n = tonumber(v, x == 'x' and 16 or 10)
    if n < 256 then
      return string.char(n)
    end
    return ''
  end)
  return s
end

local function escape(s, lazy)
  return (string.gsub(s, lazy and '([<>&])' or '(["\'<>&%c])', function(c)
    return ESCAPED_CHARS[c] or string.format('&#x%02x;', string.byte(c))
  end))
end

local function setAttribute(node, name, value)
  local attr = node.attr
  if attr then
    attr[name] = value
  else
    node.attr = {[name] = value}
  end
end

local function hasAttributes(node)
  local attr = node.attr
  if attr then
    for _ in pairs(attr) do
      return true
    end
  end
  return false
end

local function removeAttribute(node, name)
  local attr = node.attr
  if attr then
    attr[name] = nil
    if not hasAttributes(node) then
      node.attr = nil
    end
  end
end

local function hasChildren(node)
  return node[1] ~= nil
end

local Handler = class.create(function(handler)

  function handler:initialize()
    self.root = {
      name = 'ROOT'
    }
    self._stack = {self.root}
  end

  function handler:addChild(child)
    local current = self._stack[#self._stack]
    table.insert(current, child)
  end

  function handler:starttag(tag)
    local node = {
      name = tag.name
    }
    if tag.attrs then
      local attr = {}
      for k, v in pairs(tag.attrs) do
        attr[k] = unescape(v)
      end
      node.attr = attr
    end
    self:addChild(node)
    table.insert(self._stack, node)
  end

  function handler:endtag(tag)
    local current = self._stack[#self._stack]
    if current.name ~= tag.name then
      error('Expecting end tag '..'"'..current.name..'" but found "'..tag.name..'"')
    end
    table.remove(self._stack)
  end

  function handler:text(text)
    self:addChild(unescape(text))
  end

  handler.cdata = handler.addChild

end)

local function getNodeType(node)
  local t = type(node)
  if t == 'table' then
    return 'element'
  elseif t == 'string' or t == 'number' or t == 'boolean' then
    return 'text'
  end
  return ''
end

local function toString(buffer, node)
  local nodeType = getNodeType(node)
  if nodeType == 'text' then
    buffer:append(escape(tostring(node), true))
  elseif nodeType == 'element' then
    buffer:append('<', node.name)
    if node.attr then
      -- TODO sort attributes by name to get consistent output
      for k, v in pairs(node.attr) do
        buffer:append(' ', k, '="', escape(tostring(v)), '"')
      end
    end
    if hasChildren(node) then
      buffer:append('>')
      for _, child in ipairs(node) do
        toString(buffer, child)
      end
      buffer:append('</', node.name, '>')
    else
      buffer:append(' />')
    end
  end
end

local xml = {}

--- Returns the XML encoded string representing the specified table.
-- @tparam table xmlTable The XML table to encode.
-- @return the encoded XML as a string.
-- @usage
--local xml = require('jls.util.xml')
--xml.encode({name = 'a', {name = 'b', attr = {c = 'c'}, 'A value'}})
-- -- Returns '<a><b c="c">A value</b></a>'
function xml.encode(xmlTable)
  local buffer = StringBuffer:new()
  if xmlTable.name then
    toString(buffer, xmlTable)
  else
    for _, child in ipairs(xmlTable) do
      toString(buffer, child)
    end
  end
  return buffer:toString()
end

--- Returns the XML table representing the specified XML string.
-- @tparam string xmlString The XML string to decode.
-- @return the decoded XML as a table.
-- @usage
--local xml = require('jls.util.xml')
--xml.decode('<a><b c="c">A value</b></a>')
-- -- Returns {name = 'a', {name = 'b', attr = {c = 'c'}, 'A value'}}
function xml.decode(xmlString)
  local handler = Handler:new()
  local options = {
    stripWS = true, -- Indicates if whitespaces should be striped or not
    expandEntities = false,
    errorHandler = function(errMsg, pos)
      error(string.format("%s [char=%d]\n", errMsg or "Parse Error", pos))
    end
  }
  local parser = XmlParser.new(handler, options)
  parser:parse(xmlString)
  return handler.root[1]
end

local function collectNamespaces(node, parentNamespaces)
  local namespaces = {}
  if parentNamespaces then
    setmetatable(namespaces, {__index = parentNamespaces})
  end
  if node.attr then
    for k, v in pairs(node.attr) do
      local nsPrefix, prefix = getLocalName(k)
      if prefix == 'xmlns' then
        namespaces[nsPrefix] = v
      elseif nsPrefix == 'xmlns' then
        namespaces[''] = v
      end
    end
  end
  return namespaces
end

local function changePrefix(node, toPrefix, fromPrefix)
  local localName, currentPrefix = getLocalName(node.name)
  if currentPrefix == fromPrefix then
    node.name = composeQName(toPrefix, localName)
  end
  for _, child in ipairs(node) do
    if getNodeType(child) == 'element' then
      changePrefix(child, toPrefix, fromPrefix)
    end
  end
end

function xml.setNamespace(xmlTable, name, prefix)
  local localName, currentPrefix = getLocalName(xmlTable.name)
  if prefix then
    setAttribute(xmlTable, composeQName('xmlns', prefix), name)
    if currentPrefix then
      removeAttribute(xmlTable, composeQName('xmlns', currentPrefix))
    else
      removeAttribute(xmlTable, 'xmlns')
    end
  else
    setAttribute(xmlTable, 'xmlns', name)
  end
  changePrefix(xmlTable, prefix, currentPrefix)
  return xmlTable
end

return xml
