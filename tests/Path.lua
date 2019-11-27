local lu = require('luaunit')

local Path = require('jls.io.Path')

function test_new()
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

function test_getPathName()
    local f
    f = Path:new('my_name')
    lu.assertEquals(f:getPathName(), 'my_name')
    local osPath = 'some_path'..Path.separator..'my_name'
    f = Path:new('some_path/my_name')
    lu.assertEquals(f:getPathName(), osPath)
    f = Path:new('some_path\\my_name')
    lu.assertEquals(f:getPathName(), osPath)
    f = Path:new('some_path/my_name/')
    lu.assertEquals(f:getPathName(), osPath)
end

function test_toString()
    lu.assertEquals(Path:new('my_name'):toString(), 'my_name')
end

function test_getName()
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

function test_getExtension()
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

function test_isAbsolute()
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

function test_getParent()
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

function test_normalizePath()
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
end

os.exit(lu.LuaUnit.run())
