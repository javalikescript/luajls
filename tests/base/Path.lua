local lu = require('luaunit')

local Path = require('jls.io.Path')

function Test_new()
    local f
    f = Path:new('my_name')
    lu.assertEquals(f:getPathName(), 'my_name')
    local osPath = 'some_path'..Path.separator..'my_name'
    f = Path:new('some_path', 'my_name')
    lu.assertEquals(f:getPathName(), osPath)
    f = Path:new(Path:new('some_path'), 'my_name')
    lu.assertEquals(f:getPathName(), osPath)
    f = Path:new(Path:new('some_path'), '')
    lu.assertEquals(f:getPathName(), 'some_path')
end

function Test_getPathName()
    local f
    f = Path:new('my_name')
    lu.assertEquals(f:getPathName(), 'my_name')
    f = Path:new('some_path/my_name')
    lu.assertEquals(f:getPathName(), 'some_path/my_name')
    f = Path:new('some_path\\my_name')
    lu.assertEquals(f:getPathName(), 'some_path\\my_name')
    f = Path:new('some_path/my_name/')
    lu.assertEquals(f:getPathName(), 'some_path/my_name')
end

function Test_toString()
    lu.assertEquals(Path:new('my_name'):toString(), 'my_name')
end

function Test_getName()
    local f
    f = Path:new('my_name')
    lu.assertEquals(f:getName(), 'my_name')
    f = Path:new('some_path/my_name')
    lu.assertEquals(f:getName(), 'my_name')
    f = Path:new('some_path\\my_name')
    lu.assertEquals(f:getName(), 'my_name')
    f = Path:new('some_path/my_name/')
    lu.assertEquals(f:getName(), 'my_name')
end

function Test_getExtension()
    local f
    f = Path:new('my_name')
    lu.assertEquals(f:getExtension(), nil)
    f = Path:new('my_name.ext')
    lu.assertEquals(f:getExtension(), 'ext')
    f = Path:new('some_path/my_name')
    lu.assertEquals(f:getExtension(), nil)
    f = Path:new('some_path.ext/my_name')
    lu.assertEquals(f:getExtension(), nil)
    f = Path:new('my_name.ext.ext')
    lu.assertEquals(f:getExtension(), 'ext')
    f = Path:new('my_name.')
    lu.assertEquals(f:getExtension(), '')
end

function Test_getBaseName()
    local f
    f = Path:new('my_name')
    lu.assertEquals(f:getBaseName(), 'my_name')
    f = Path:new('my_name.ext')
    lu.assertEquals(f:getBaseName(), 'my_name')
    f = Path:new('some_path/my_name')
    lu.assertEquals(f:getBaseName(), 'my_name')
    f = Path:new('some_path.ext/my_name')
    lu.assertEquals(f:getBaseName(), 'my_name')
    f = Path:new('my_name.ext.ext')
    lu.assertEquals(f:getBaseName(), 'my_name.ext')
    f = Path:new('my_name.')
    lu.assertEquals(f:getBaseName(), 'my_name')
end

function Test_isAbsolute()
    local f
    f = Path:new('my_name')
    lu.assertEquals(f:isAbsolute(), false)
    f = Path:new('/my_name')
    lu.assertEquals(f:isAbsolute(), true)
    f = Path:new('C:\\my_name')
    lu.assertEquals(f:isAbsolute(), true)
end

local function assertParentEquals(f, p)
    lu.assertEquals(Path:new(f):getParent(), Path:new(p):getPathName())
end

function Test_getParent()
    lu.assertEquals(Path:new('a'):getParent(), nil)
    lu.assertEquals(Path:new('a/b'):getParent(), 'a')
    assertParentEquals('a/b/c', 'a/b')
    lu.assertEquals(Path:new('/'):getParent(), nil)
    assertParentEquals('/a', '/')
    assertParentEquals('/a/b', '/a')
    assertParentEquals('/a/b/c', '/a/b')
    lu.assertEquals(Path:new('C:\\'):getParent(), nil)
    assertParentEquals('C:\\a', 'C:\\')
end

function Test_normalizePath()
    lu.assertEquals(Path.normalizePath('/a/.b'), '/a/.b')
    lu.assertEquals(Path.normalizePath('/.a/b'), '/.a/b')
    lu.assertEquals(Path.normalizePath('/a./b'), '/a./b')
    lu.assertEquals(Path.normalizePath('/a/b'), '/a/b')
    lu.assertEquals(Path.normalizePath('/a/b/.'), '/a/b')
    lu.assertEquals(Path.normalizePath('/a/./b'), '/a/b')
    --lu.assertEquals(Path.normalizePath('/a/././b'), '/a/b')
    --lu.assertEquals(Path.normalizePath('/a/./././b'), '/a/b')
    lu.assertEquals(Path.normalizePath('/./a/b'), '/a/b')
    lu.assertEquals(Path.normalizePath('/./a/./b'), '/a/b')
    lu.assertEquals(Path.normalizePath('a/b'), 'a/b')
    lu.assertEquals(Path.normalizePath('a/b/.'), 'a/b')
    lu.assertEquals(Path.normalizePath('a/./b'), 'a/b')
    lu.assertEquals(Path.normalizePath('./a/b'), 'a/b')
    lu.assertEquals(Path.normalizePath('./a/./b'), 'a/b')

    lu.assertEquals(Path.normalizePath('/a/..b'), '/a/..b')
    lu.assertEquals(Path.normalizePath('/..a/b'), '/..a/b')
    lu.assertEquals(Path.normalizePath('/a../b'), '/a../b')
    lu.assertEquals(Path.normalizePath('/a/b/c/..'), '/a/b')
    lu.assertEquals(Path.normalizePath('/a/b/../c'), '/a/c')
    --lu.assertEquals(Path.normalizePath('/a/b/../../c'), '/c')
    lu.assertEquals(Path.normalizePath('/a/../b/c'), '/b/c')
    lu.assertEquals(Path.normalizePath('/../b/c'), '/../b/c')
    lu.assertEquals(Path.normalizePath('a/b/c/..'), 'a/b')
    lu.assertEquals(Path.normalizePath('a/b/../c'), 'a/c')
    lu.assertEquals(Path.normalizePath('a/../b/c'), 'b/c')
    lu.assertEquals(Path.normalizePath('../b/c'), '../b/c')

    lu.assertEquals(Path.normalizePath('.'), '.')
    lu.assertEquals(Path.normalizePath('/.'), '/')
    lu.assertEquals(Path.normalizePath('/a/..'), '/')
    lu.assertEquals(Path.normalizePath('/a/b/..'), '/a')
    lu.assertEquals(Path.normalizePath('C:\\.'), 'C:\\')
    lu.assertEquals(Path.normalizePath('C:\\a\\..'), 'C:\\')
    lu.assertEquals(Path.normalizePath('C:\\a\\b\\..'), 'C:\\a')
    lu.assertEquals(Path.normalizePath('C:\\..'), 'C:\\..')
    lu.assertEquals(Path.normalizePath('/..'), '/..')
end

os.exit(lu.LuaUnit.run())
