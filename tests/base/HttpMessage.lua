local lu = require('luaunit')

local HttpMessage = require('jls.net.http.HttpMessage')
local HttpHeaders = require('jls.net.http.HttpHeaders')
local StringBuffer = require('jls.lang.StringBuffer')
local StreamHandler = require('jls.io.StreamHandler')
local Date = require('jls.util.Date')
local CONST = HttpMessage.CONST

local function newRequest()
  local message = HttpMessage:new()
  message:setMethod('GET')
  message:setTarget('/')
  return message
end

function Test_parseLine_request()
  local message = HttpMessage:new()
  lu.assertTrue(message:parseLine('GET /path?x=1 HTTP/1.1'))
  lu.assertTrue(message:isRequest())
  lu.assertFalse(message:isResponse())
  lu.assertEquals(message:getMethod(), 'GET')
  lu.assertEquals(message:getTarget(), '/path?x=1')
  lu.assertEquals(message:getVersion(), 'HTTP/1.1')
end

function Test_parseLine_response()
  local message = HttpMessage:new()
  lu.assertTrue(message:parseLine('HTTP/1.1 200 OK'))
  lu.assertFalse(message:isRequest())
  lu.assertTrue(message:isResponse())
  lu.assertEquals(message:getStatusCode(), 200)
  lu.assertEquals(message:getReasonPhrase(), 'OK')
end

function Test_parseLine_invalid()
  local message = HttpMessage:new()
  lu.assertFalse(message:parseLine('garbage'))
  lu.assertFalse(message:isRequest())
  lu.assertFalse(message:isResponse())
  lu.assertEquals(message:getStatusCode(), 0)
  lu.assertEquals(message:getReasonPhrase(), '')
end

function Test_formatLine()
  local request = newRequest()
  lu.assertEquals(request:formatLine(), 'GET / HTTP/1.1')
  local response = HttpMessage:new()
  response:setStatusCode(200, 'OK')
  lu.assertEquals(response:formatLine(), 'HTTP/1.1 200 OK')
  lu.assertFalse(pcall(function()
    return HttpMessage:new():formatLine()
  end))
end

function Test_version()
  local message = HttpMessage:new()
  lu.assertEquals(message:getVersion(), CONST.VERSION_1_1)
  message:setVersion('HTTP/1.0')
  lu.assertEquals(message:getVersion(), 'HTTP/1.0')
  lu.assertFalse(pcall(function()
    message:setVersion('invalid')
  end))
end

function Test_statusCode()
  local message = HttpMessage:new()
  message:setStatusCode(200)
  lu.assertEquals(message:getStatusCode(), 200)
  message:setStatusCode('404', 'Not Found')
  lu.assertEquals(message:getStatusCode(), 404)
  lu.assertEquals(message:getReasonPhrase(), 'Not Found')
  message:setStatusCode(500, 12)
  lu.assertEquals(message:getStatusCode(), 500)
  lu.assertEquals(message:getReasonPhrase(), 'Not Found')
  message:setReasonPhrase(12)
  lu.assertEquals(message:getReasonPhrase(), 'Not Found')
  message:setReasonPhrase('Internal Server Error')
  lu.assertEquals(message:getReasonPhrase(), 'Internal Server Error')
end

function Test_cacheControl()
  local message = HttpMessage:new()
  message:setCacheControl(true)
  lu.assertEquals(message:getHeader(CONST.HEADER_CACHE_CONTROL), 'public, max-age=604800, must-revalidate')
  message:setCacheControl(false)
  lu.assertEquals(message:getHeader(CONST.HEADER_CACHE_CONTROL), 'no-store, no-cache, must-revalidate')
  message:setCacheControl(0)
  lu.assertEquals(message:getHeader(CONST.HEADER_CACHE_CONTROL), 'public, max-age=0, must-revalidate')
  message:setCacheControl('no-cache')
  lu.assertEquals(message:getHeader(CONST.HEADER_CACHE_CONTROL), 'no-cache')
  lu.assertFalse(pcall(function()
    message:setCacheControl({})
  end))
end

function Test_lastModified()
  local message = HttpMessage:new()
  message:setLastModified(1000)
  lu.assertEquals(message:getLastModified(), 1000)
  message:setLastModified(Date:new(2000))
  lu.assertEquals(message:getLastModified(), 2000)
  message:setLastModified('Tue, 01 Jan 1980 00:00:00 GMT')
  lu.assertEquals(message:getLastModified(), 315532800000)
  lu.assertFalse(pcall(function()
    message:setLastModified(true)
  end))
end

function Test_targetPathQuery()
  local message = newRequest()
  message:setTarget('/a/b?x=1&y=2')
  lu.assertEquals(message:getTargetPath(), '/a/b')
  lu.assertEquals(message:getTargetQuery(), 'x=1&y=2')
  lu.assertEquals(message:getSearchParams().x, '1')
  lu.assertEquals(message:getSearchParam('x'), '1')
  lu.assertNil(message:getSearchParam('missing'))
end

function Test_ifModifiedSince()
  local message = HttpMessage:new()
  lu.assertNil(message:getIfModifiedSince())
  message:setHeader('If-Modified-Since', Date:new(1000):toRFC822String(true))
  lu.assertEquals(message:getIfModifiedSince(), 1999)
  message:setHeader('If-Modified-Since', 'not a date')
  lu.assertNil(message:getIfModifiedSince())
end

function Test_contentLength()
  local message = HttpMessage:new()
  lu.assertNil(message:getContentLength())
  message:setContentLength(12)
  lu.assertEquals(message:getContentLength(), 12)
end

function Test_connection()
  local message = HttpMessage:new()
  lu.assertEquals(message:getConnection(), CONST.CONNECTION_KEEP_ALIVE)
  message:setVersion('HTTP/1.0')
  lu.assertEquals(message:getConnection(), CONST.CONNECTION_CLOSE)
  message:setHeader(CONST.HEADER_CONNECTION, 'Keep-Alive')
  lu.assertEquals(message:getConnection(), 'keep-alive')
end

function Test_contentTypeAndEncoding()
  local message = HttpMessage:new()
  lu.assertNil(message:getContentType())
  message:setContentType('Text/HTML; charset=utf-8')
  lu.assertEquals(message:getContentType(), 'text/html')
  message:setHeader(CONST.HEADER_TRANSFER_ENCODING, 'chunked')
  lu.assertTrue(message:hasChunkedTransferEncoding())
end

function Test_bodyStreamHandler()
  local message = HttpMessage:new()
  lu.assertIs(message:getBodyStreamHandler(), StreamHandler.null)
  local handler = StreamHandler:new()
  message:setBodyStreamHandler(handler)
  lu.assertIs(message:getBodyStreamHandler(), handler)
  message:setBodyStreamHandler(nil)
  lu.assertIs(message:getBodyStreamHandler(), StreamHandler.null)
  lu.assertFalse(pcall(function()
    message:setBodyStreamHandler(12)
  end))
end

function Test_body()
  local message = HttpMessage:new()
  lu.assertEquals(message:getBody(), '')
  lu.assertTrue(message:isBodyEmpty())
  message:setBody('abcd')
  lu.assertEquals(message:getBody(), 'abcd')
  lu.assertEquals(message:getBodyLength(), 4)
  lu.assertFalse(message:isBodyEmpty())
  message:setBody(nil)
  lu.assertEquals(message:getBody(), '')
  message:setBody(StringBuffer:new('xyz'))
  lu.assertEquals(message:getBody(), 'xyz')
  lu.assertFalse(pcall(function()
    message:setBody(12)
  end))
end

function Test_writeBodyCallback()
  local message = HttpMessage:new()
  message:setBody('abcdef')
  local calls = {}
  local handler = StreamHandler:new()
  function handler:onData(value, ends)
    calls[#calls + 1] = {value, ends}
  end
  message:setBodyStreamHandler(handler)
  message:writeBodyCallback(2)
  lu.assertEquals(calls[1], {'ab', false})
  lu.assertEquals(calls[2], {'cd', false})
  lu.assertEquals(calls[3], {'ef', true})
  lu.assertEquals(calls[4], {nil, nil})
end

function Test_applyBodyLength()
  local message = HttpMessage:new()
  message:applyBodyLength()
  lu.assertEquals(message:getHeader(CONST.HEADER_CONTENT_LENGTH), '0')

  local request = newRequest()
  request:setBody('abcd')
  request:applyBodyLength()
  lu.assertEquals(request:getHeader(CONST.HEADER_CONTENT_LENGTH), '4')

  local streaming = newRequest()
  streaming:onWriteBodyStreamHandler(function() end)
  streaming:applyBodyLength()
  lu.assertEquals(streaming:getHeader(CONST.HEADER_TRANSFER_ENCODING), 'chunked')

  local encoded = HttpMessage:new()
  encoded:setHeader(CONST.HEADER_CONTENT_ENCODING, 'gzip')
  encoded:applyBodyLength()
  lu.assertEquals(encoded:getHeader(CONST.HEADER_TRANSFER_ENCODING), 'chunked')
end

function Test_applyContentEncoding()
  local message = HttpMessage:new()
  local sh = StreamHandler:new()
  lu.assertIs(message:applyContentEncoding(sh), sh)
  message:setHeader(CONST.HEADER_CONTENT_ENCODING, 'identity')
  lu.assertIs(message:applyContentEncoding(sh), sh)
  message:setHeader(CONST.HEADER_CONTENT_ENCODING, 'unknown-encoding')
  local result, err = message:applyContentEncoding(sh)
  lu.assertNil(result)
  lu.assertStrContains(err, 'unsupported content encoding')
end

function Test_onWriteBodyStreamHandler()
  local message = HttpMessage:new()
  local called = false
  local promise = message:onWriteBodyStreamHandler(function()
    called = true
  end)
  lu.assertNil(promise)
  message:writeBodyCallback()
  lu.assertTrue(called)
  local p = message:onWriteBodyStreamHandler()
  lu.assertTrue(require('jls.lang.Promise'):isInstance(p))
end

function Test_consume_text_json()
  local message = HttpMessage:new()
  local reason
  message:consume():catch(function(r)
    reason = r
  end)
  lu.assertEquals(reason, 'message body not available')
  local textReason
  message:text():catch(function(r)
    textReason = r
  end)
  lu.assertEquals(textReason, 'message body not available')
  local jsonReason
  message:json():catch(function(r)
    jsonReason = r
  end)
  lu.assertEquals(jsonReason, 'message body not available')
end

function Test_close()
  local message = HttpMessage:new()
  message:close()
end

function Test_headers()
  local message = HttpMessage:new()
  lu.assertTrue(HttpHeaders:isInstance(message))
  message:setHeader('a', 'A')
  lu.assertEquals(message:getHeader('a'), 'A')
end

os.exit(lu.LuaUnit.run())
