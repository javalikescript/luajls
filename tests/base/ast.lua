local lu = require('luaunit')

local ast = require('jls.util.ast')

function Test_parse_generate()
  lu.assertEquals(ast.generate(ast.parse("local a = 2 // 2")), "local a=2//2;")
end

function Test_parseExpression_generate()
  lu.assertEquals(ast.generate(ast.parseExpression("2 // 2")), "2//2")
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
