local lu = require('luaunit')

local HttpServer = require('jls.net.http.HttpServer')

function Test_computeIndex()
  local computeIndex = HttpServer.HttpContext.computeIndex
  lu.assertEquals(computeIndex(''), 0)
  lu.assertEquals(computeIndex('/'), 1)
  lu.assertEquals(computeIndex('/(.*)'), 1)
  lu.assertEquals(computeIndex('/(%.*)%...'), 4)
  lu.assertEquals(computeIndex('/?(.*)'), 0)
  lu.assertEquals(computeIndex('/static/(.*)'), 8)
  lu.assertEquals(computeIndex('/addon/([^/]*)/?(.*)'), 7)
end

os.exit(lu.LuaUnit.run())
