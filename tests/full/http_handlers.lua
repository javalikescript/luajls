local lu = require('luaunit')

local loop = require('jls.lang.loader').load('loop', 'tests', false, true)
local RestHttpHandler = require('jls.net.http.handler.RestHttpHandler')
local HttpServer = require('jls.net.http.HttpServer')
local HttpClient = require('jls.net.http.HttpClient')
local event = require('jls.lang.event')
local Promise = require('jls.lang.Promise')

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
    return connectSendReceiveClose( HttpClient:new({ url = url..'/users/bar/greetings' }), responses)
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
  lu.assertEquals(responses[3]:getBody(), 'Hello Sally')
  lu.assertEquals(responses[4]:getBody(), '{"firstname":"John"}')
  lu.assertEquals(responses[5]:getBody(), '{"bar":{"firstname":"Sally"},"foo":{"firstname":"John"}}')
  lu.assertEquals(responses[6]:getBody(), 'delay done')
end

os.exit(lu.LuaUnit.run())
