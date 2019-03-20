local lu = require('luaunit')

local URL = require("jls.net.URL")

function assertParsedURL(url, urlt)
    local t = URL.parse(url)
    lu.assertEquals(t, urlt)
end

function test_parse()
    local t = URL.parse('http://www.host.name')
    lu.assertEquals(t.scheme, 'http')
end

function test_parse_common_http()
    assertParsedURL('http://www.host.name', {
        scheme = 'http',
        host = 'www.host.name',
        port = 80,
        path = ''
    })
    assertParsedURL('http://www.host.name/', {
        scheme = 'http',
        host = 'www.host.name',
        port = 80,
        path = '/'
    })
    assertParsedURL('http://www.host.name:8080/', {
        scheme = 'http',
        host = 'www.host.name',
        port = 8080,
        path = '/'
    })
    assertParsedURL('http://127.0.0.1/', {
        scheme = 'http',
        host = '127.0.0.1',
        port = 80,
        path = '/'
    })
    assertParsedURL('http://127.0.0.1:8080/', {
        scheme = 'http',
        host = '127.0.0.1',
        port = 8080,
        path = '/'
    })
    assertParsedURL('http://[::1]/', {
        scheme = 'http',
        host = '::1',
        port = 80,
        path = '/'
    })
    assertParsedURL('http://[::1]:8080/', {
        scheme = 'http',
        host = '::1',
        port = 8080,
        path = '/'
    })
    assertParsedURL('http://www.host.name/index.html', {
        scheme = 'http',
        host = 'www.host.name',
        port = 80,
        path = '/index.html'
    })
    assertParsedURL('http://www.host.name/some/path/', {
        scheme = 'http',
        host = 'www.host.name',
        port = 80,
        path = '/some/path/'
    })
end

function test_parse_common_authentication()
    assertParsedURL('http://nick@www.host.name', {
        scheme = 'http',
        user = 'nick',
        host = 'www.host.name',
        port = 80,
        path = ''
    })
    assertParsedURL('http://nick:changeit@www.host.name', {
        scheme = 'http',
        user = 'nick',
        password = 'changeit',
        host = 'www.host.name',
        port = 80,
        path = ''
    })
end

function test_parse_http_query()
    assertParsedURL('http://www.host.name/?aquery', {
        scheme = 'http',
        host = 'www.host.name',
        port = 80,
        path = '/',
        query = 'aquery'
    })
    assertParsedURL('http://www.host.name/index.html?aquery', {
        scheme = 'http',
        host = 'www.host.name',
        port = 80,
        path = '/index.html',
        query = 'aquery'
    })
end

function test_parse_http_fragment()
    assertParsedURL('http://www.host.name/#afragment', {
        scheme = 'http',
        host = 'www.host.name',
        port = 80,
        path = '/',
        fragment = 'afragment'
    })
    assertParsedURL('http://www.host.name/index.html#afragment', {
        scheme = 'http',
        host = 'www.host.name',
        port = 80,
        path = '/index.html',
        fragment = 'afragment'
    })
end

function test_parse_http_query_fragment()
    assertParsedURL('http://www.host.name/?aquery#afragment', {
        scheme = 'http',
        host = 'www.host.name',
        port = 80,
        path = '/',
        query = 'aquery',
        fragment = 'afragment'
    })
    assertParsedURL('http://www.host.name/index.html?aquery#afragment', {
        scheme = 'http',
        host = 'www.host.name',
        port = 80,
        path = '/index.html',
        query = 'aquery',
        fragment = 'afragment'
    })
end

function test_parse_https()
    assertParsedURL('https://www.host.name/', {
        scheme = 'https',
        host = 'www.host.name',
        port = 443,
        path = '/'
    })
    assertParsedURL('https://127.0.0.1/', {
        scheme = 'https',
        host = '127.0.0.1',
        port = 443,
        path = '/'
    })
end

function test_format()
    lu.assertEquals(URL.format({
        scheme = 'http',
        host = 'www.host.name'
    }), 'http://www.host.name')
end

function test_format_common_http()
    lu.assertEquals(URL.format({
        scheme = 'http',
        host = 'www.host.name',
        port = 8080
    }), 'http://www.host.name:8080')
    lu.assertEquals(URL.format({
        scheme = 'http',
        host = '127.0.0.1'
    }), 'http://127.0.0.1')
    lu.assertEquals(URL.format({
        scheme = 'http',
        host = '::1'
    }), 'http://[::1]')
end

function test_format_common_authentication()
    lu.assertEquals(URL.format({
        scheme = 'http',
        user = 'nick',
        host = 'www.host.name'
    }), 'http://nick@www.host.name')
    lu.assertEquals(URL.format({
        scheme = 'http',
        user = 'nick',
        password = 'changeit',
        host = 'www.host.name'
    }), 'http://nick:changeit@www.host.name')
end

function test_getHost()
    local u = URL:new('http://www.host.name')
    lu.assertEquals(u:getHost(), 'www.host.name')
end

function test_getPath()
    lu.assertEquals(URL:new('http://hostname'):getPath(), '')
    lu.assertEquals(URL:new('http://hostname/'):getPath(), '/')
    lu.assertEquals(URL:new('http://hostname/some_path'):getPath(), '/some_path')
    lu.assertEquals(URL:new('http://hostname/some_path?some_query'):getPath(), '/some_path')
    lu.assertEquals(URL:new('http://hostname/some_path#some_fragment'):getPath(), '/some_path')
end

function test_getFile()
    lu.assertEquals(URL:new('http://hostname'):getFile(), '')
    lu.assertEquals(URL:new('http://hostname/'):getFile(), '/')
    lu.assertEquals(URL:new('http://hostname/some_path'):getFile(), '/some_path')
    lu.assertEquals(URL:new('http://hostname/some_path?some_query'):getFile(), '/some_path?some_query')
    lu.assertEquals(URL:new('http://hostname/some_path#some_fragment'):getFile(), '/some_path')
    lu.assertEquals(URL:new('http://hostname/?some_query'):getFile(), '/?some_query')
end

function test_getQuery()
    lu.assertEquals(URL:new('http://hostname'):getQuery(), nil)
    lu.assertEquals(URL:new('http://hostname/some_path?some_query'):getQuery(), 'some_query')
    lu.assertEquals(URL:new('http://hostname/?some_query'):getQuery(), 'some_query')
end

os.exit(lu.LuaUnit.run())
