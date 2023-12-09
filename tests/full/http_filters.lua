local lu = require('luaunit')

local SessionHttpFilter = require('jls.net.http.filter.SessionHttpFilter')
local HttpExchange = require('jls.net.http.HttpExchange')

local function getCookie(cookies, name)
  for _, cookie in ipairs(cookies) do
    local key, value = string.match(cookie, '^([^=]+)=([^;]*)')
    if key == name then
      return value
    end
  end
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
