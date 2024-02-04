local lxpLib = require('lxp')

local strings = require('jls.util.strings')

local function startElement(p, name, attrs)
	local handler = p:getcallbacks().handler
  handler:startElement(name, attrs)
end

local function endElement(p, name)
	local handler = p:getcallbacks().handler
  handler:endElement(name)
end

local function cdata(p, text)
  text = strings.strip(text)
  if text ~= '' then
    local handler = p:getcallbacks().handler
    handler:cdata(text)
  end
end

return {
  new = function(_, handler)
    -- see https://lunarmodules.github.io/luaexpat/manual.html
    -- lxp.new(callbacks [, separator[, merge_character_data]])
    return lxpLib.new({
      StartElement = startElement,
      EndElement = endElement,
      CharacterData = cdata,
      _nonstrict = true,
      handler = handler
	  }, nil, true)
  end
}