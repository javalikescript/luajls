local lu = require('luaunit')

local logger = require('jls.lang.logger')
local Codec = require('jls.util.Codec')
local HttpFilter = require('jls.net.http.HttpFilter')
local HttpExchange = require('jls.net.http.HttpExchange')
local HttpMessage = require('jls.net.http.HttpMessage')
local BasicAuthenticationHttpFilter = require('jls.net.http.filter.BasicAuthenticationHttpFilter')
local LogHttpFilter = require('jls.net.http.filter.LogHttpFilter')
local PathHttpFilter = require('jls.net.http.filter.PathHttpFilter')
local SessionHttpFilter = require('jls.net.http.filter.SessionHttpFilter')

local HTTP_CONST = HttpMessage.CONST

local function newAuthExchange(authorization)
  local exchange = HttpExchange:new()
  local request = exchange:getRequest()
  request:setMethod(HTTP_CONST.METHOD_GET)
  request:setTarget('/')
  if authorization then
    request:setHeader(HTTP_CONST.HEADER_AUTHORIZATION, authorization)
  end
  return exchange
end

local function basicCredentials(user, password)
  return 'Basic '..Codec.encode('base64', user..':'..password)
end

local function newPathExchange(path)
  local exchange = HttpExchange:new()
  exchange:getRequest():setTarget(path)
  return exchange
end

local function newInnerFilter()
  return HttpFilter:new(function()
    return true
  end)
end

local function getCookie(cookies, name)
  for _, cookie in ipairs(cookies) do
    local key, value = string.match(cookie, '^([^=]+)=([^;]*)')
    if key == name then
      return value
    end
  end
end

function Test_default()
  local filter = HttpFilter:new()
  lu.assertNil(filter:doFilter({}))
  lu.assertNil(filter:close())
end

function Test_function()
  local seen
  local filter = HttpFilter:new(function(_, exchange)
    seen = exchange
    return false
  end)
  local exchange = {}
  lu.assertIsFalse(filter:doFilter(exchange))
  lu.assertIs(seen, exchange)
end

function Test_filter()
  local calls = {}
  local filters = {
    HttpFilter:new(function()
      calls[#calls + 1] = 1
    end),
    HttpFilter:new(function()
      calls[#calls + 1] = 2
    end),
    HttpFilter:new(function()
      calls[#calls + 1] = 3
      return false
    end),
    HttpFilter:new(function()
      calls[#calls + 1] = 4
    end)
  }
  lu.assertIsFalse(HttpFilter.filter({}, filters))
  lu.assertEquals(calls, {1, 2, 3})
  lu.assertIsTrue(HttpFilter.filter({}, {}))
end

function Test_multiple()
  local calls = {}
  local filter = HttpFilter.multiple(function()
    calls[#calls + 1] = 'a'
  end)
  lu.assertIs(filter:addFilter(HttpFilter:new(function()
    calls[#calls + 1] = 'b'
  end)), filter)
  lu.assertIsTrue(filter:doFilter())
  lu.assertEquals(calls, {'a', 'b'})
  filter:addFilter(HttpFilter:new(function()
    return false
  end))
  lu.assertIsFalse(filter:doFilter())
end

function Test_basicAuth()
  local filter = HttpFilter.basicAuth({user = 'password'})
  lu.assertTrue(BasicAuthenticationHttpFilter:isInstance(filter))
end

function Test_byPath()
  local inner = HttpFilter:new()
  local filter = HttpFilter.byPath(inner)
  lu.assertTrue(PathHttpFilter:isInstance(filter))
  lu.assertIs(filter.filter, inner)
end

function Test_missingAuthorization()
  local filter = BasicAuthenticationHttpFilter:new({user = 'password'})
  local exchange = newAuthExchange()
  lu.assertIsFalse(filter:doFilter(exchange))
  local response = exchange:getResponse()
  lu.assertEquals(response:getStatusCode(), HTTP_CONST.HTTP_UNAUTHORIZED)
  lu.assertEquals(response:getHeader(HTTP_CONST.HEADER_WWW_AUTHENTICATE), 'Basic realm="User Visible Realm"')
end

function Test_validCredentials()
  local filter = BasicAuthenticationHttpFilter:new({alice = 'secret', bob = 'pass'})
  local exchange = newAuthExchange(basicCredentials('alice', 'secret'))
  lu.assertNil(filter:doFilter(exchange))
  lu.assertEquals(exchange:getResponse():getStatusCode(), HTTP_CONST.HTTP_OK)
end

function Test_invalidCredentials()
  local filter = BasicAuthenticationHttpFilter:new({alice = 'secret'})
  local failedUser
  filter.onAuthorizationFailed = function(_, _, user)
    failedUser = user
  end
  local exchange = newAuthExchange(basicCredentials('alice', 'wrong'))
  lu.assertIsFalse(filter:doFilter(exchange))
  lu.assertEquals(failedUser, 'alice')
  lu.assertEquals(exchange:getResponse():getStatusCode(), HTTP_CONST.HTTP_UNAUTHORIZED)
end

function Test_functionCredentials()
  local seenUser, seenPassword
  local filter = BasicAuthenticationHttpFilter:new(function(user, password)
    seenUser, seenPassword = user, password
    return password == 'pwd'
  end, 'My Realm')
  local exchange = newAuthExchange(basicCredentials('bob', 'pwd'))
  lu.assertNil(filter:doFilter(exchange))
  lu.assertEquals(seenUser, 'bob')
  lu.assertEquals(seenPassword, 'pwd')
  lu.assertEquals(filter.realm, 'My Realm')
end

function Test_anyCredentials()
  local filter = BasicAuthenticationHttpFilter:new()
  local exchange = newAuthExchange(basicCredentials('who', 'ever'))
  lu.assertNil(filter:doFilter(exchange))
end

function Test_badScheme()
  local filter = BasicAuthenticationHttpFilter:new()
  local exchange = newAuthExchange('Bearer token')
  lu.assertIsFalse(filter:doFilter(exchange))
  lu.assertEquals(exchange:getResponse():getStatusCode(), HTTP_CONST.HTTP_BAD_REQUEST)
end

function Test_noColon()
  local filter = BasicAuthenticationHttpFilter:new()
  local exchange = newAuthExchange('Basic '..Codec.encode('base64', 'nocolon'))
  lu.assertIsFalse(filter:doFilter(exchange))
  lu.assertEquals(exchange:getResponse():getStatusCode(), HTTP_CONST.HTTP_BAD_REQUEST)
end

function Test_noLevelHeader()
  local filter = LogHttpFilter:new()
  local before = logger:getConfig()
  local exchange = HttpExchange:new()
  lu.assertNil(filter:doFilter(exchange))
  lu.assertEquals(logger:getConfig(), before)
end

function Test_levelHeader()
  local filter = LogHttpFilter:new()
  local before = logger:getConfig()
  local exchange = HttpExchange:new()
  exchange:getRequest():setHeader('jls-logger-level', 'warn')
  lu.assertNil(filter:doFilter(exchange))
  lu.assertEquals(logger:getConfig(), 'WARN')
  exchange:close()
  lu.assertEquals(logger:getConfig(), before)
end

function Test_noPattern()
  local filter = PathHttpFilter:new(newInnerFilter())
  lu.assertIsTrue(filter:doFilter(newPathExchange('/anything')))
end

function Test_allow()
  local filter = PathHttpFilter:new(newInnerFilter())
  lu.assertIs(filter:allow('^/api'), filter)
  lu.assertIsTrue(filter:doFilter(newPathExchange('/api/items')))
  lu.assertNil(filter:doFilter(newPathExchange('/other')))
end

function Test_allowPath()
  local filter = PathHttpFilter:new(newInnerFilter())
  lu.assertIs(filter:allowPath('/a.b'), filter)
  lu.assertIsTrue(filter:doFilter(newPathExchange('/a.b')))
  lu.assertNil(filter:doFilter(newPathExchange('/axb')))
end

function Test_exclude()
  local filter = PathHttpFilter:new(newInnerFilter())
  lu.assertIs(filter:exclude('^/private'), filter)
  lu.assertNil(filter:doFilter(newPathExchange('/private/data')))
  lu.assertIsTrue(filter:doFilter(newPathExchange('/public')))
end

function Test_excludePath()
  local filter = PathHttpFilter:new(newInnerFilter())
  lu.assertIs(filter:excludePath('/secret'), filter)
  lu.assertNil(filter:doFilter(newPathExchange('/secret')))
  lu.assertIsTrue(filter:doFilter(newPathExchange('/visible')))
end

function Test_excludedWins()
  local filter = PathHttpFilter:new(newInnerFilter(), {'^/api'}, {'^/api/admin'})
  lu.assertNil(filter:doFilter(newPathExchange('/api/admin')))
  lu.assertIsTrue(filter:doFilter(newPathExchange('/api/items')))
  lu.assertNil(filter:doFilter(newPathExchange('/other')))
end

function Test_HttpSession()
  local filter = SessionHttpFilter:new()
  local exchange = HttpExchange:new()
  filter:doFilter(exchange)
  local session = exchange:getSession()
  lu.assertNotIsNil(session)
  local cookies = exchange:getResponse():getHeader('set-cookie')
  lu.assertNotIsNil(cookies)
  local sessionId = getCookie(cookies, filter.name)
  lu.assertNotIsNil(sessionId)
  lu.assertEquals(session:getId(), sessionId)
  exchange = HttpExchange:new()
  exchange:getRequest():setHeader('cookie', filter.name..'='..sessionId)
  lu.assertEquals(exchange:getRequest():getCookie(filter.name), sessionId)
  filter:doFilter(exchange)
  session = exchange:getSession()
  lu.assertNotIsNil(session)
  lu.assertEquals(session:getId(), sessionId)
  session:invalidate()
  filter:doFilter(exchange)
  session = exchange:getSession()
  lu.assertNotIsNil(session)
  lu.assertNotEquals(session:getId(), sessionId)
end

os.exit(lu.LuaUnit.run())
