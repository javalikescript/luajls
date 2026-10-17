local lu = require('luaunit')

local HttpExchange = require('jls.net.http.HttpExchange')
local HttpHeaders = require('jls.net.http.HttpHeaders')
local HttpMessage = require('jls.net.http.HttpMessage')
local Promise = require('jls.lang.Promise')
local CONST = HttpMessage.CONST

local function newExchange()
  local exchange = HttpExchange:new()
  exchange:getRequest():setMethod('GET')
  exchange:getRequest():setTarget('/')
  return exchange
end

function Test_message_accessors()
  local exchange = newExchange()
  lu.assertTrue(HttpMessage:isInstance(exchange:getRequest()))
  lu.assertTrue(HttpMessage:isInstance(exchange:getResponse()))
  lu.assertEquals(exchange:getRequestMethod(), 'GET')
  lu.assertEquals(exchange:getResponse():getStatusCode(), 200)
  exchange:setContext('ctx')
  lu.assertEquals(exchange:getContext(), 'ctx')
  exchange:setSession('sess')
  lu.assertEquals(exchange:getSession(), 'sess')
end

function Test_requestHeadersCopy()
  local exchange = newExchange()
  exchange:getRequest():setHeader('X-Test', 'value')
  local headers = exchange:getRequestHeaders()
  lu.assertTrue(HttpHeaders:isInstance(headers))
  lu.assertFalse(headers == exchange:getRequest())
  lu.assertEquals(headers:getHeader('x-test'), 'value')
end

function Test_context_paths()
  local exchange = newExchange()
  exchange:getRequest():setTarget('/a/b')
  exchange:setContext({
    getArguments = function(_, name)
      return 'arg:'..name
    end,
    replacePath = function(_, name)
      return 'path:'..name
    end
  })
  lu.assertEquals(exchange:getRequestArguments(), 'arg:/a/b')
  lu.assertEquals(exchange:getRequestPath(), 'path:/a/b')
end

function Test_searchParams()
  local exchange = newExchange()
  exchange:getRequest():setTarget('/?a=1')
  lu.assertEquals(exchange:getSearchParams().a, '1')
end

function Test_setResponseStatusCode()
  local exchange = newExchange()
  exchange:setResponseStatusCode(404, 'Not Found')
  lu.assertEquals(exchange:getResponse():getStatusCode(), 404)
  lu.assertEquals(exchange:getResponse():getReasonPhrase(), 'Not Found')
  exchange:setResponseStatusCode(200, 'OK', 'content')
  lu.assertEquals(exchange:getResponse():getBody(), 'content')
end

function Test_resetResponseToError()
  local exchange = newExchange()
  local oldResponse = exchange:getResponse()
  exchange:resetResponseToError('oops')
  lu.assertFalse(exchange:getResponse() == oldResponse)
  lu.assertEquals(exchange:getResponse():getStatusCode(), 500)
end

function Test_onClose()
  local exchange = newExchange()
  local closed = false
  local promise = exchange:onClose()
  lu.assertTrue(Promise:isInstance(promise))
  promise:next(function()
    closed = true
  end)
  lu.assertFalse(closed)
  lu.assertIs(exchange:onClose(), promise)
  exchange:close()
  lu.assertTrue(closed)
end

function Test_close_client()
  local exchange = newExchange()
  local closed = false
  exchange.client = {
    close = function()
      closed = true
    end
  }
  exchange:close()
  lu.assertTrue(closed)
  lu.assertNil(exchange.client)
end

function Test_getClient()
  local exchange = newExchange()
  lu.assertNil(exchange:getClient())
  local client = {}
  exchange.client = client
  lu.assertIs(exchange:getClient(), client)
  exchange.client = nil
  local http2Client = {}
  exchange.stream = {http2 = {client = http2Client}}
  lu.assertIs(exchange:getClient(), http2Client)
end

function Test_clientAsString()
  local exchange = newExchange()
  lu.assertEquals(exchange:clientAsString(), '')
  exchange.client = {
    getRemoteName = function()
      return '127.0.0.1', 8080
    end
  }
  lu.assertEquals(exchange:clientAsString(), '127.0.0.1:8080')
  exchange.client = {
    getRemoteName = function()
      return nil
    end
  }
  lu.assertEquals(exchange:clientAsString(), '')
end

function Test_handleRequest_result()
  local exchange = newExchange()
  local context = {
    handleExchange = function(_, ex)
      ex:getResponse():setStatusCode(204)
      return 42
    end
  }
  local promise = exchange:handleRequest(context)
  lu.assertTrue(Promise:isInstance(promise))
  lu.assertIs(exchange:getContext(), context)
  lu.assertEquals(exchange:getResponse():getStatusCode(), 204)
end

function Test_handleRequest_promise()
  local exchange = newExchange()
  local context = {
    handleExchange = function()
      return Promise.resolve('ok')
    end
  }
  local result
  exchange:handleRequest(context):next(function(value)
    result = value
  end)
  lu.assertEquals(result, 'ok')
end

function Test_handleRequest_rejected()
  local exchange = newExchange()
  local context = {
    handleExchange = function()
      return Promise.reject('boom')
    end
  }
  exchange:handleRequest(context)
  lu.assertEquals(exchange:getResponse():getStatusCode(), 500)
end

function Test_handleRequest_throw()
  local exchange = newExchange()
  local context = {
    handleExchange = function()
      error('bad')
    end
  }
  exchange:handleRequest(context)
  lu.assertEquals(exchange:getResponse():getStatusCode(), 500)
end

function Test_toString()
  local exchange = newExchange()
  exchange:getRequest():setHeader(CONST.HEADER_HOST, 'example.com')
  local text = exchange:toString()
  lu.assertStrContains(text, 'GET /')
  lu.assertStrContains(text, '(example.com)')
  lu.assertStrContains(text, '200')
  exchange:getRequest():setHeader(CONST.HEADER_HOST, nil)
  lu.assertStrContains(exchange:toString(), 'GET /')
  exchange.request = nil
  lu.assertStrContains(exchange:toString(), 'httpExchange:')
end

function Test_ok()
  local exchange = newExchange()
  HttpExchange.ok(exchange, 'body', 'text/plain')
  lu.assertEquals(exchange:getResponse():getStatusCode(), 200)
  lu.assertEquals(exchange:getResponse():getBody(), 'body')
  lu.assertEquals(exchange:getResponse():getContentType(), 'text/plain')
  HttpExchange.ok(exchange)
  lu.assertEquals(exchange:getResponse():getStatusCode(), 200)
end

function Test_error_helpers()
  local exchange = newExchange()
  HttpExchange.badRequest(exchange)
  lu.assertEquals(exchange:getResponse():getStatusCode(), 400)
  HttpExchange.forbidden(exchange)
  lu.assertEquals(exchange:getResponse():getStatusCode(), 403)
  HttpExchange.notFound(exchange)
  lu.assertEquals(exchange:getResponse():getStatusCode(), 404)
  lu.assertStrContains(exchange:getResponse():getBody(), exchange:getRequest():getTarget())
  HttpExchange.methodNotAllowed(exchange)
  lu.assertEquals(exchange:getResponse():getStatusCode(), 405)
  HttpExchange.internalServerError(exchange)
  lu.assertEquals(exchange:getResponse():getStatusCode(), 500)
  lu.assertEquals(exchange:getResponse():getVersion(), CONST.VERSION_1_0)
end

function Test_redirect()
  local exchange = newExchange()
  HttpExchange.redirect(exchange, '/location')
  lu.assertEquals(exchange:getResponse():getStatusCode(), 302)
  lu.assertEquals(exchange:getResponse():getHeader(CONST.HEADER_LOCATION), '/location')
  HttpExchange.redirect(exchange, '/other', 301, 'Moved', 'body')
  lu.assertEquals(exchange:getResponse():getStatusCode(), 301)
  lu.assertEquals(exchange:getResponse():getReasonPhrase(), 'Moved')
  lu.assertEquals(exchange:getResponse():getBody(), 'body')
end

function Test_response()
  local exchange = newExchange()
  HttpExchange.response(exchange, 201, 'Created', 'x')
  lu.assertEquals(exchange:getResponse():getStatusCode(), 201)
  HttpExchange.response(exchange)
  lu.assertEquals(exchange:getResponse():getStatusCode(), 200)
end

function Test_isValidSubPath()
  lu.assertTrue(HttpExchange.isValidSubPath('a/b'))
  lu.assertFalse(HttpExchange.isValidSubPath('../a'))
  lu.assertFalse(HttpExchange.isValidSubPath('a/../b'))
  lu.assertFalse(HttpExchange.isValidSubPath('a/..'))
  lu.assertFalse(HttpExchange.isValidSubPath('a\\b'))
end

function Test_methodAllowed()
  local exchange = newExchange()
  lu.assertTrue(HttpExchange.methodAllowed(exchange, 'GET'))
  lu.assertTrue(HttpExchange.methodAllowed(exchange, {'POST', 'GET'}))
  lu.assertFalse(HttpExchange.methodAllowed(exchange, 'POST'))
  lu.assertEquals(exchange:getResponse():getStatusCode(), 405)
end

os.exit(lu.LuaUnit.run())
