local lu = require('luaunit')

local loop = require('jls.lang.loopWithTimeout')
local event = require('jls.lang.event')
local Promise = require('jls.lang.Promise')
local system = require('jls.lang.system')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local RouterHttpHandler = require('jls.net.http.handler.RouterHttpHandler')
local ProxyHttpHandler = require('jls.net.http.handler.ProxyHttpHandler')
local HttpServer = require('jls.net.http.HttpServer')
local HttpClient = require('jls.net.http.HttpClient')
local Date = require('jls.util.Date')
local File = require('jls.io.File')

local TEST_PATH = 'tests/full'
local TMP_PATH = TEST_PATH..'/tmp'

--local logger = require('jls.lang.logger'); logger:setLevel(logger.FINE)

local function getTmpDir(forCreation)
  local tmpDir = File:new(TMP_PATH)
  if tmpDir:isDirectory() then
    if forCreation then
      if not tmpDir:deleteRecursive() then
        error('Cannot delete tmp dir')
      end
    else
      if not tmpDir:deleteAll() then
        error('Cannot delete tmp dir content')
      end
    end
  elseif not forCreation then
    if not tmpDir:mkdir() then
      error('Cannot create tmp dir')
    end
  end
  return tmpDir
end

local function fetch(client, resource, options, responses)
  return client:fetch(resource, options):next(function(response)
    return response:text():next(function()
      if responses then
        table.insert(responses, response)
      end
      return response
    end)
  end)
end

local function shift(responses)
  return table.remove(responses, 1)
end

local function assertReponse(response, statusCode, body)
  if statusCode then
    lu.assertEquals(response:getStatusCode(), statusCode)
  end
  if body then
    lu.assertEquals(response:getBody(), body)
  end
end

local table_pack = table.pack or function(...)
  return {n = select('#', ...), ...}
end

local function close(...)
  local args = table_pack(...)
  for i = 1, args.n do
    local v = args[i]
    if v then
      v:close()
    end
  end
end

local function createRouterHandler(users)
  return RouterHttpHandler:new({
    user = {
      ['{+user}?method=GET'] = function(_, userId)
        return users[userId]
      end,
      ['{*}'] = {
        ['(user)?method=GET'] = function(_, user)
          return user
        end
      }
    },
    users = {
      [''] = function(exchange)
        return users
      end,
      -- additional handler
      ['{+}?method=GET'] = function(exchange, userId)
        exchange:setAttribute('user', users[userId])
      end,
      ['{userId}'] = {
        ['(user)?method=GET'] = function(_, user)
          return user
        end,
        ['(userId, requestJson)?method=POST,PUT&:Content-Type^=application/json'] = function(_, userId, requestJson)
          users[userId] = requestJson
        end,
        ['(userId, requestXml)?method=POST,PUT&:Content-Type^=text/xml'] = function(_, userId, requestXml)
          users[userId] = requestXml and requestXml.attr
        end,
        -- will be available at /rest/users/{userId}/greetings
        ['greetings(user)?method=GET'] = function(_, user)
          if user then
            return 'Hello '..user.firstname
          end
          return 'User not found'
        end
      },
    },
    ['query-filter?query=test'] = function()
      return 'query test'
    end,
    ['query-param-filter?q:a=test'] = function()
      return 'query param test'
    end,
    ['query-param-capture(p1, p2)?q:a+=p1&q:b-=p2'] = function(_, p1, p2)
      if p2 then
        return 'query params are '..tostring(p1)..' and '..tostring(p2)
      end
      return 'query param is '..tostring(p1)
    end,
    delay = function()
      return Promise:new(function(resolve)
        event:setTimeout(function()
          resolve('delay done')
        end, 100)
      end)
    end,
  })
end

function Test_rest()
  local responses = {}
  local users = {}
  local url
  local httpServer = HttpServer:new()
  httpServer:createContext('/(.*)', createRouterHandler(users))
  local httpClient
  local fetchCount = 0
  local function addFetch(resource, options)
    fetchCount = fetchCount + 1
    return fetch(httpClient, resource, options, responses)
  end
  httpServer:bind('::', 0):next(function()
    local port = select(2, httpServer:getAddress())
    url = 'http://127.0.0.1:'..tostring(port)
    httpClient = HttpClient:new(url)
  end):next(function()
    return addFetch('/foo')
  end):next(function()
    return addFetch('/user/foo')
  end):next(function()
    return addFetch('/users/foo', {
      method = 'PUT',
      headers = {
        ['Content-Type'] = 'application/json; charset=utf-8',
      },
      body = '{"firstname": "John"}',
    })
  end):next(function()
    return addFetch('/users/bar', {
      method = 'PUT',
      headers = {
        ['Content-Type'] = 'text/xml',
      },
      body = '<user firstname="Sally" />',
    })
  end):next(function()
    return addFetch('/users/bar/greetings')
  end):next(function()
    return addFetch('/users/foo')
  end):next(function()
    return addFetch('/user/foo')
  end):next(function()
    return addFetch('/users')
  end):next(function()
    return addFetch('/query-filter?test')
  end):next(function()
    return addFetch('/query-param-filter?a=test')
  end):next(function()
    return addFetch('/query-param-filter?a=no')
  end):next(function()
    return addFetch('/query-param-capture?a=hi')
  end):next(function()
    return addFetch('/query-param-capture?a=hi&b=Yo')
  end):next(function()
    return addFetch('/delay')
  end):catch(function(reason)
    print('Unexpected error', reason)
  end):finally(function()
    close(httpClient, httpServer)
  end)
  if not loop(function()
    close(httpClient, httpServer)
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(#responses, fetchCount)
  lu.assertEquals(shift(responses):getStatusCode(), 404)
  lu.assertEquals(shift(responses):getStatusCode(), 404)
  lu.assertEquals(shift(responses):getStatusCode(), 200)
  lu.assertEquals(shift(responses):getStatusCode(), 200)
  lu.assertEquals(shift(responses):getBody(), 'Hello Sally')
  lu.assertEquals(shift(responses):getBody(), '{"firstname":"John"}')
  lu.assertEquals(shift(responses):getBody(), '{"firstname":"John"}')
  lu.assertEquals(shift(responses):getBody(), '{"bar":{"firstname":"Sally"},"foo":{"firstname":"John"}}')
  lu.assertEquals(shift(responses):getBody(), 'query test')
  lu.assertEquals(shift(responses):getBody(), 'query param test')
  lu.assertEquals(shift(responses):getStatusCode(), 404)
  lu.assertEquals(shift(responses):getBody(), 'query param is hi')
  lu.assertEquals(shift(responses):getBody(), 'query params are hi and Yo')
  lu.assertEquals(shift(responses):getBody(), 'delay done')
end

function Test_file()
  local tmpDir = getTmpDir()
  local responses = {}
  local url
  local content = '123456789 123456789 123456789 Hello World !'
  local httpClient
  local fetchCount = 0
  local function addFetch(resource, options)
    fetchCount = fetchCount + 1
    return fetch(httpClient, resource, options, responses)
  end
  local httpServer = HttpServer:new()
  httpServer:createContext('/(.*)', FileHttpHandler:new(tmpDir, 'rwl'))
  httpServer:bind('::', 0):next(function()
    local port = select(2, httpServer:getAddress())
    url = 'http://127.0.0.1:'..tostring(port)
    httpClient = HttpClient:new(url)
  end):next(function()
    return addFetch('/file.txt')
  end):next(function()
    return addFetch('/file.txt', { method = 'PUT', body = content, })
  end):next(function()
    return addFetch('/file.txt')
  end):next(function()
    return addFetch('/file.txt', {
      headers = {
        ['If-Modified-Since'] = Date:new(system.currentTimeMillis() + 60000):toRFC822String(true),
      }
    })
  end):next(function()
    return addFetch('/file.txt', {
      headers = {
        ['If-Modified-Since'] = Date:new(system.currentTimeMillis() - 60000):toRFC822String(true),
      }
    })
  end):next(function()
    return addFetch('/file.txt', { headers = { Range = 'bytes=0-' } })
  end):next(function()
    return addFetch('/file.txt', { headers = { Range = 'bytes=0-9' } })
  end):next(function()
    return addFetch('/file.txt', { headers = { Range = 'bytes=4-5' } })
  end):next(function()
    return addFetch('/file.txt', { headers = { Range = 'bytes=20-' } })
  end):next(function()
    return addFetch('/file.txt', { headers = { destination = url..'/file-new.txt' }, method = 'MOVE' })
  end):next(function()
    return addFetch('/file.txt')
  end):next(function()
    return addFetch('/file-new.txt')
  end):next(function()
    return addFetch('/file-new.txt', { method = 'HEAD' })
  end):next(function()
    return addFetch('/file-new.txt', { method = 'DELETE' })
  end):next(function()
    return addFetch('/file-new.txt')
  end):catch(function(reason)
    print('Unexpected error', reason)
  end):finally(function()
    close(httpClient, httpServer)
  end)
  if not loop(function()
    close(httpClient, httpServer)
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(#responses, fetchCount)
  assertReponse(shift(responses), 404)
  assertReponse(shift(responses), 200) -- PUT
  assertReponse(shift(responses), 200, content)
  assertReponse(shift(responses), 304) -- If-Modified-Since +1mn
  assertReponse(shift(responses), 200, content) -- If-Modified-Since -1mn
  assertReponse(shift(responses), 206, content) -- Range 0-
  assertReponse(shift(responses), 206, '123456789 ') -- Range 0-9
  assertReponse(shift(responses), 206, '56') -- Range 4-5
  assertReponse(shift(responses), 206, '123456789 Hello World !') -- Range 20-
  assertReponse(shift(responses), 201) -- MOVE
  assertReponse(shift(responses), 404)
  assertReponse(shift(responses), 200, content)
  assertReponse(shift(responses), 200, '') -- HEAD
  assertReponse(shift(responses), 200) -- DELETE
  assertReponse(shift(responses), 404)
  tmpDir:deleteRecursive()
end

function Test_proxy()
  local responses = {}
  local users = {}
  local httpClient, url, host, port, proxyUrl, proxyHost, proxyPort
  local httpServer = HttpServer:new()
  local httpProxy = HttpServer:new()
  httpServer:bind('::', 0):next(function()
    host = '127.0.0.1'
    port = select(2, httpServer:getAddress())
    url = string.format('http://%s:%d/', host, port)
    httpServer:createContext('/rest/(.*)', createRouterHandler(users))
    return httpProxy:bind('::', 0)
  end):next(function()
    proxyHost = '127.0.0.1'
    proxyPort = select(2, httpProxy:getAddress())
    proxyUrl = string.format('http://%s:%d/', proxyHost, proxyPort)
    httpProxy:createContext('/rprox/(.*)', ProxyHttpHandler:new():configureReverse(url..'rest/'))
    httpProxy:createContext('(.*)', ProxyHttpHandler:new():configureForward(true))
  end):next(function()
    httpClient = HttpClient:new(proxyUrl)
    return fetch(httpClient, '/rprox/users/foo', {
      method = 'PUT',
      headers = {
        ['Content-Type'] = 'application/json',
      },
      body = '{"firstname": "John"}',
    }, responses)
  end):next(function()
    return fetch(httpClient, '/rprox/users/foo/greetings', {}, responses)
  end):next(function()
    return fetch(httpClient, url..'rest/users/foo/greetings', {}, responses)
  end):finally(function()
    close(httpClient, httpProxy, httpServer)
  end)
  if not loop(function()
    close(httpClient, httpProxy, httpServer)
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(shift(responses):getStatusCode(), 200)
  lu.assertEquals(shift(responses):getBody(), 'Hello John')
  lu.assertEquals(shift(responses):getBody(), 'Hello John')
end

os.exit(lu.LuaUnit.run())
