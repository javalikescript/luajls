local lu = require('luaunit')

local ast = require('jls.util.ast')

function Test_parse_generate()
  lu.assertEquals(ast.generate(ast.parse("local a = 2 // 2")), "local a=2//2;")
end

function Test_parseExpression_generate()
  lu.assertEquals(ast.generate(ast.parseExpression("2 // 2")), "2//2")
end

function Test_parse_generate_51()
  lu.assertEquals(ast.generate(ast.traverse(ast.parse("local a = 1 // 2"), ast.toLua51)), "local a=compat.fdiv(1,2);")
  lu.assertEquals(ast.generate(ast.traverse(ast.parse("local a = 1 ~ 2"), ast.toLua51)), "local a=compat.bxor(1,2);")
  lu.assertEquals(ast.generate(ast.traverse(ast.parse("local a = 1 & 2"), ast.toLua51)), "local a=compat.band(1,2);")
  lu.assertEquals(ast.generate(ast.traverse(ast.parse("local a = 1 | 2"), ast.toLua51)), "local a=compat.bor(1,2);")
  lu.assertEquals(ast.generate(ast.traverse(ast.parse("local a = ~2"), ast.toLua51)), "local a=compat.bnot(2);")
  lu.assertEquals(ast.generate(ast.traverse(ast.parse("local a = 1 & (2 ~ 3)"), ast.toLua51)), "local a=compat.band(1,compat.bxor(2,3));")
  lu.assertEquals(ast.generate(ast.traverse(ast.parse("local a = _ENV.b"), ast.toLua51)), "local a=b;")
end

function Test_traverse()
  local tree = ast.parse("local a = 2 // 2")
  ast.traverse(tree, function(astNode)
    if astNode.type == 'binary' and astNode.operator == '//' then
      return {
        type = 'call',
        callee = {
          type = 'lookup',
          object = { type = 'identifier', name = 'math' },
          member = { type = 'literal', value = 'floor' },
        },
        arguments = { { type = 'binary', operator = '/', left = astNode.left, right = astNode.right } },
      }
      end
  end)
  lu.assertEquals(ast.generate(tree), "local a=math.floor(2/2);")
end

os.exit(lu.LuaUnit.run())
