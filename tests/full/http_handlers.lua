local lu = require('luaunit')

local loop = require('jls.lang.loopWithTimeout')
local event = require('jls.lang.event')
local Promise = require('jls.lang.Promise')
local system = require('jls.lang.system')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local RestHttpHandler = require('jls.net.http.handler.RestHttpHandler')
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

local function connectSendReceiveClose(httpClient, responses)
  return httpClient:connect():next(function()
    return httpClient:sendReceive()
  end):next(function(response)
    httpClient:close()
    if responses then
      table.insert(responses, response)
    end
    return response
  end)
end

local function shift(responses)
  return table.remove(responses, 1)
end

local function assertReponse(response, statusCode, body)
  if body then
    lu.assertEquals(response:getBody(), body)
  end
  if statusCode then
    lu.assertEquals(response:getStatusCode(), statusCode)
  end
end

function Test_rest()
  local responses = {}
  local users = {}
  local url
  local httpServer = HttpServer:new()
  httpServer:createContext('/(.*)', RestHttpHandler:new({
    users = {
      [''] = function(exchange)
        return users
      end,
      -- additional handler
      ['{+}?method=GET'] = function(exchange, userId)
        exchange:setAttribute('user', users[userId])
      end,
      ['{userId}'] = {
        ['(user)?method=GET'] = function(exchange, user)
          return user
        end,
        ['(userId, requestJson)?method=POST,PUT&Content-Type=application/json'] = function(exchange, userId, requestJson)
          users[userId] = requestJson
        end,
        ['(userId, requestXml)?method=POST,PUT&Content-Type=text/xml'] = function(exchange, userId, requestXml)
          users[userId] = requestXml and requestXml.attr
        end,
        -- will be available at /rest/users/{userId}/greetings
        ['greetings(user)?method=GET'] = function(exchange, user)
          return 'Hello '..user.firstname
        end,
      },
    },
    delay = function(exchange)
      return Promise:new(function(resolve, reject)
        event:setTimeout(function()
          resolve('delay done')
        end, 100)
      end)
    end,
  }))
  httpServer:bind('::', 0):next(function()
    local port = select(2, httpServer:getAddress())
    url = 'http://127.0.0.1:'..tostring(port)
  end):next(function()
    return connectSendReceiveClose(HttpClient:new({
      url = url..'/users/foo',
      method = 'PUT',
      headers = {
        ['Content-Type'] = 'application/json',
      },
      body = '{"firstname": "John"}',
    }), responses)
  end):next(function()
    return connectSendReceiveClose(HttpClient:new({
      url = url..'/users/bar',
      method = 'PUT',
      headers = {
        ['Content-Type'] = 'text/xml',
      },
      body = '<user firstname="Sally" />',
    }), responses)
  end):next(function()
    return connectSendReceiveClose(HttpClient:new({ url = url..'/users/bar/greetings' }), responses)
  end):next(function()
    return connectSendReceiveClose(HttpClient:new({ url = url..'/users/foo' }), responses)
  end):next(function()
    return connectSendReceiveClose(HttpClient:new({ url = url..'/users' }), responses)
  end):next(function()
    return connectSendReceiveClose(HttpClient:new({ url = url..'/delay' }), responses)
  end):next(function()
    httpServer:close()
  end):catch(function(reason)
    print('Unexpected error', reason)
  end)
  if not loop(function()
    httpServer:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(#responses, 6)
  lu.assertEquals(shift(responses):getStatusCode(), 200)
  lu.assertEquals(shift(responses):getStatusCode(), 200)
  lu.assertEquals(shift(responses):getBody(), 'Hello Sally')
  lu.assertEquals(shift(responses):getBody(), '{"firstname":"John"}')
  lu.assertEquals(shift(responses):getBody(), '{"bar":{"firstname":"Sally"},"foo":{"firstname":"John"}}')
  lu.assertEquals(shift(responses):getBody(), 'delay done')
end

function Test_file()
  local tmpDir = getTmpDir()
  local responses = {}
  local url, fileUrl, newFileUrl
  local content = '123456789 123456789 123456789 Hello World !'
  local httpServer = HttpServer:new()
  httpServer:createContext('/(.*)', FileHttpHandler:new(tmpDir, 'rwl'))
  httpServer:bind('::', 0):next(function()
    local port = select(2, httpServer:getAddress())
    url = 'http://127.0.0.1:'..tostring(port)
    fileUrl = url..'/file.txt'
    newFileUrl = url..'/file-new.txt'
  end):next(function()
    return connectSendReceiveClose(HttpClient:new({ url = fileUrl }), responses)
  end):next(function()
    return connectSendReceiveClose(HttpClient:new({ url = fileUrl, method = 'PUT', body = content }), responses)
  end):next(function()
    return connectSendReceiveClose(HttpClient:new({ url = fileUrl }), responses)
  end):next(function()
    return connectSendReceiveClose(HttpClient:new({
      url = fileUrl,
      headers = {
        ['If-Modified-Since'] = Date:new(system.currentTimeMillis() + 60000):toRFC822String(true),
      },
      method = 'GET'
    }), responses)
  end):next(function()
    return connectSendReceiveClose(HttpClient:new({
      url = fileUrl,
      headers = {
        ['If-Modified-Since'] = Date:new(system.currentTimeMillis() - 60000):toRFC822String(true),
      },
      method = 'GET'
    }), responses)
  end):next(function()
    return connectSendReceiveClose(HttpClient:new({ url = fileUrl, headers = { Range = 'bytes=0-' }, method = 'GET' }), responses)
  end):next(function()
    return connectSendReceiveClose(HttpClient:new({ url = fileUrl, headers = { Range = 'bytes=0-9' }, method = 'GET' }), responses)
  end):next(function()
    return connectSendReceiveClose(HttpClient:new({ url = fileUrl, headers = { Range = 'bytes=4-5' }, method = 'GET' }), responses)
  end):next(function()
    return connectSendReceiveClose(HttpClient:new({ url = fileUrl, headers = { Range = 'bytes=20-' }, method = 'GET' }), responses)
  end):next(function()
    return connectSendReceiveClose(HttpClient:new({ url = fileUrl, headers = { destination = newFileUrl }, method = 'MOVE' }), responses)
  end):next(function()
    return connectSendReceiveClose(HttpClient:new({ url = fileUrl }), responses)
  end):next(function()
    return connectSendReceiveClose(HttpClient:new({ url = newFileUrl }), responses)
  end):next(function()
    return connectSendReceiveClose(HttpClient:new({ url = newFileUrl, method = 'HEAD' }), responses)
  end):next(function()
    return connectSendReceiveClose(HttpClient:new({ url = newFileUrl, method = 'DELETE' }), responses)
  end):next(function()
    return connectSendReceiveClose(HttpClient:new({ url = newFileUrl }), responses)
  end):next(function()
    httpServer:close()
  end):catch(function(reason)
    print('Unexpected error', reason)
  end)
  if not loop(function()
    httpServer:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(#responses, 15)
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

os.exit(lu.LuaUnit.run())
