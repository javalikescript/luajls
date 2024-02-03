local XmlParser = require('XmlParser') -- xml2lua parser

local function errorHandler(errMsg, pos)
  error(string.format("%s [char=%d]\n", errMsg or "Parse Error", pos))
end

local function starttag(handler, tag)
  handler:startElement(tag.name, tag.attrs)
end

local function endtag(handler, tag)
  handler:endElement(tag.name)
end

return {
  new = function(_, handler)
    handler.starttag = starttag
    handler.endtag = endtag
    return XmlParser.new(handler, {
      stripWS = true, -- Indicates if whitespaces should be striped or not
      expandEntities = false,
      errorHandler = errorHandler
    })
  end
}