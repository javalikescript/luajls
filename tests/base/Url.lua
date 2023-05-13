local lu = require('luaunit')

local Url = require("jls.net.Url")

local function assertParsedUrl(url, urlt)
  local t = Url.parse(url)
  lu.assertEquals(t, urlt)
end

local function assertFromToString(url)
  local u = Url.fromString(url)
  lu.assertNotNil(u, 'Url from "'..url..'"')
  lu.assertEquals(u:toString(), url)
end

function Test_parse()
  local t = Url.parse('http://www.host.name')
  lu.assertEquals(t.scheme, 'http')
end

function Test_parse_common_http()
  assertParsedUrl('http://www.host.name', {
    scheme = 'http',
    host = 'www.host.name',
    port = 80,
    path = ''
  })
  assertParsedUrl('http://www.host.name/', {
    scheme = 'http',
    host = 'www.host.name',
    port = 80,
    path = '/'
  })
  assertParsedUrl('http://www.host.name:8080/', {
    scheme = 'http',
    host = 'www.host.name',
    port = 8080,
    path = '/'
  })
  assertParsedUrl('http://127.0.0.1/', {
    scheme = 'http',
    host = '127.0.0.1',
    port = 80,
    path = '/'
  })
  assertParsedUrl('http://127.0.0.1:8080/', {
    scheme = 'http',
    host = '127.0.0.1',
    port = 8080,
    path = '/'
  })
  assertParsedUrl('http://[::1]/', {
    scheme = 'http',
    host = '::1',
    port = 80,
    path = '/'
  })
  assertParsedUrl('http://[::1]:8080/', {
    scheme = 'http',
    host = '::1',
    port = 8080,
    path = '/'
  })
  assertParsedUrl('http://www.host.name/index.html', {
    scheme = 'http',
    host = 'www.host.name',
    port = 80,
    path = '/index.html'
  })
  assertParsedUrl('http://www.host.name/some/path/', {
    scheme = 'http',
    host = 'www.host.name',
    port = 80,
    path = '/some/path/'
  })
end

function Test_parse_common_authentication()
  assertParsedUrl('http://nick@www.host.name', {
    scheme = 'http',
    userinfo = 'nick',
    host = 'www.host.name',
    port = 80,
    path = ''
  })
  assertParsedUrl('http://nick:changeit@www.host.name', {
    scheme = 'http',
    username = 'nick',
    password = 'changeit',
    host = 'www.host.name',
    port = 80,
    path = ''
  })
  assertParsedUrl('http://nick:@www.host.name', {
    scheme = 'http',
    username = 'nick',
    password = '',
    host = 'www.host.name',
    port = 80,
    path = ''
  })
end

function Test_parse_http_query()
  assertParsedUrl('http://www.host.name/?aquery', {
    scheme = 'http',
    host = 'www.host.name',
    port = 80,
    path = '/',
    query = 'aquery'
  })
  assertParsedUrl('http://www.host.name/index.html?aquery', {
    scheme = 'http',
    host = 'www.host.name',
    port = 80,
    path = '/index.html',
    query = 'aquery'
  })
end

function Test_parse_http_fragment()
  assertParsedUrl('http://www.host.name/#afragment', {
    scheme = 'http',
    host = 'www.host.name',
    port = 80,
    path = '/',
    fragment = 'afragment'
  })
  assertParsedUrl('http://www.host.name/index.html#afragment', {
    scheme = 'http',
    host = 'www.host.name',
    port = 80,
    path = '/index.html',
    fragment = 'afragment'
  })
end

function Test_parse_http_query_fragment()
  assertParsedUrl('http://www.host.name/?aquery#afragment', {
    scheme = 'http',
    host = 'www.host.name',
    port = 80,
    path = '/',
    query = 'aquery',
    fragment = 'afragment'
  })
  assertParsedUrl('http://www.host.name/index.html?aquery#afragment', {
    scheme = 'http',
    host = 'www.host.name',
    port = 80,
    path = '/index.html',
    query = 'aquery',
    fragment = 'afragment'
  })
end

function Test_parse_https()
  assertParsedUrl('https://www.host.name/', {
    scheme = 'https',
    host = 'www.host.name',
    port = 443,
    path = '/'
  })
  assertParsedUrl('https://127.0.0.1/', {
    scheme = 'https',
    host = '127.0.0.1',
    port = 443,
    path = '/'
  })
end

function Test_format()
  lu.assertEquals(Url.format({
    scheme = 'http',
    host = 'www.host.name'
  }), 'http://www.host.name')
end

function Test_format_common_http()
  lu.assertEquals(Url.format({
    scheme = 'http',
    host = 'www.host.name',
    port = 8080
  }), 'http://www.host.name:8080')
  lu.assertEquals(Url.format({
    scheme = 'http',
    host = '127.0.0.1'
  }), 'http://127.0.0.1')
  lu.assertEquals(Url.format({
    scheme = 'http',
    host = '::1'
  }), 'http://[::1]')
end

function Test_format_common_authentication()
  lu.assertEquals(Url.format({
    scheme = 'http',
    username = 'nick',
    host = 'www.host.name'
  }), 'http://nick@www.host.name')
  lu.assertEquals(Url.format({
    scheme = 'http',
    userinfo = 'nick',
    host = 'www.host.name'
  }), 'http://nick@www.host.name')
  lu.assertEquals(Url.format({
    scheme = 'http',
    user = 'nick',
    host = 'www.host.name'
  }), 'http://nick@www.host.name')
  lu.assertEquals(Url.format({
    scheme = 'http',
    username = 'nick',
    password = 'changeit',
    host = 'www.host.name'
  }), 'http://nick:changeit@www.host.name')
  lu.assertEquals(Url.format({
    scheme = 'http',
    userinfo = 'nick:changeit',
    host = 'www.host.name'
  }), 'http://nick:changeit@www.host.name')
end

function Test_format_query()
  lu.assertEquals(Url.format({
    scheme = 'http',
    host = 'www.host.name',
    query = 'a=b'
  }), 'http://www.host.name?a=b')
end

function Test_format_query_values()
  lu.assertEquals(Url.format({
    scheme = 'http',
    host = 'www.host.name',
    queryValues = {
      a = 'b'
    }
  }), 'http://www.host.name?a=b')
  lu.assertEquals(Url.format({
    scheme = 'http',
    host = 'www.host.name',
    queryValues = {
      a = 'b',
      c = 'd'
    }
  }), 'http://www.host.name?a=b&c=d')
  lu.assertEquals(Url.format({
    scheme = 'http',
    host = 'www.host.name',
    query = 'a=b',
    queryValues = {
      c = 'd'
    }
  }), 'http://www.host.name?a=b&c=d')
end

function Test_getHost()
  local u = Url:new('http://www.host.name')
  lu.assertEquals(u:getHost(), 'www.host.name')
end

function Test_getPath()
  lu.assertEquals(Url:new('http://hostname'):getPath(), '')
  lu.assertEquals(Url:new('http://hostname/'):getPath(), '/')
  lu.assertEquals(Url:new('http://hostname/some_path'):getPath(), '/some_path')
  lu.assertEquals(Url:new('http://hostname/some_path?some_query'):getPath(), '/some_path')
  lu.assertEquals(Url:new('http://hostname/some_path#some_fragment'):getPath(), '/some_path')
end

function Test_getFile()
  lu.assertEquals(Url:new('http://hostname'):getFile(), '/')
  lu.assertEquals(Url:new('http://hostname/'):getFile(), '/')
  lu.assertEquals(Url:new('http://hostname/some_path'):getFile(), '/some_path')
  lu.assertEquals(Url:new('http://hostname/some_path?some_query'):getFile(), '/some_path?some_query')
  lu.assertEquals(Url:new('http://hostname/some_path#some_fragment'):getFile(), '/some_path')
  lu.assertEquals(Url:new('http://hostname/?some_query'):getFile(), '/?some_query')
end

function Test_getQuery()
  lu.assertEquals(Url:new('http://hostname'):getQuery(), nil)
  lu.assertEquals(Url:new('http://hostname/some_path?some_query'):getQuery(), 'some_query')
  lu.assertEquals(Url:new('http://hostname/?some_query'):getQuery(), 'some_query')
end

function Test_encodeURI()
  lu.assertEquals(Url.encodeURI('http://hostname/?a=b#c'), 'http://hostname/?a=b#c')
end

function Test_encodePercent()
  lu.assertEquals(Url.encodePercent(''), '')
  lu.assertEquals(Url.encodePercent('aA0'), 'aA0')
  lu.assertEquals(Url.encodePercent('http://hostname/?a=b#c'), 'http%3A%2F%2Fhostname%2F%3Fa%3Db%23c')
  lu.assertEquals(Url.encodePercent('\t\r\n'), '%09%0D%0A')
end

function Test_decodePercent()
  lu.assertEquals(Url.decodePercent(''), '')
  lu.assertEquals(Url.decodePercent('aA0'), 'aA0')
  lu.assertEquals(Url.decodePercent('http%3A%2F%2Fhostname%2F%3Fa%3Db%23c'), 'http://hostname/?a=b#c')
  lu.assertEquals(Url.decodePercent('%09%0D%0A'), '\t\r\n')
end

function Test_toString()
  assertFromToString('http://hostname')
  assertFromToString('http://hostname/')
  assertFromToString('http://hostname:8080/')
  assertFromToString('http://hostname/some_path')
  assertFromToString('http://hostname/some_path?some_query')
  assertFromToString('http://hostname/some_path#some_fragment')
  assertFromToString('http://hostname/?some_query')
  assertFromToString('http://username:password@hostname')
  assertFromToString('http://username:password@hostname:8080')
  assertFromToString('file:///path')
  assertFromToString('file:path')
  assertFromToString('file:/path')
  assertFromToString('file://hostname/path')
end

function Test_fromString()
  lu.assertNil(Url.fromString('something'))
  lu.assertEquals(Url.fromString('http://hostname/'):toString(), 'http://hostname/')
end

function _Test_encode_decode_perf()
  local randomChars = require('tests.randomChars')
  local time = require('tests.time')
  local samples = {}
  for _ = 1, 10000 do
    table.insert(samples, randomChars(math.random(5, 500)))
  end
  print('time', 'user', 'mem')
  print(time(function()
    for _, s in ipairs(samples) do
      lu.assertEquals(Url.decodePercent(Url.encodePercent(s)), s)
    end
  end))
end

os.exit(lu.LuaUnit.run())
