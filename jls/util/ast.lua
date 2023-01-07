--- Abstract Syntax Tree (AST) utility module.
-- This module allows to parse Lua into AST, manipulate AST and to generate Lua from AST.
--
-- The AST is represented using Lua table.
--
-- The types are: "assignment", "binary", "block", "break", "call", "declaration", "for", "function", "goto", "identifier", "if", "label", "literal", "lookup", "repeat", "return", "table", "unary", "vararg", "while"
--
-- The operators are: "+", "-", "*", "/", "//", "^", "%", "&", "~", "|", ">>", "<<", "..", "<", "<=", ">", ">=", "==", "~=", "and", "or", "-", "not", "#", "~"
--
-- The table fields are: adjustToOne, arguments, attribute, body, bodyFalse, bodyTrue, callee, condition, declaration, expression, fields, kind, label, left, member, method, name, names, object, operator, parameters, right, statements, targets, type, value, values
--
-- @module jls.util.ast

local dumbParser = require('dumbParser')

local ast = {}

--- Returns the AST representing the specified Lua code.
-- @tparam string lua the Lua code to parse.
-- @treturn table the AST representing the Lua.
function ast.parse(lua)
  return ast.traverse(dumbParser.parse(lua), ast.clean)
end

--- Returns the AST representing the specified Lua expression.
-- @tparam string lua the Lua expression to parse.
-- @treturn table the AST representing the Lua.
function ast.parseExpression(lua)
  return dumbParser.parseExpression(lua)
end

-- parseExpression

--- Returns the Lua code representing the specified AST.
-- @tparam table tree the AST.
-- @treturn string the Lua code representing the AST.
function ast.generate(tree)
  return dumbParser.toLua(tree)
end

--- Walks through the specified AST calling the callback function for each node.
-- The function is called with the AST node, if the return value is a table then it will replace the current AST node.
-- @tparam table tree the AST to walk through.
-- @tparam function callback the callback function.
-- @treturn table the AST.
function ast.traverse(tree, callback)
  return tree, dumbParser.traverseTree(tree, function(node, parent, container, key)
    local action, newNode = callback(node)
    if type(action) == 'table' then
      container[key] = action
      action = nil
    elseif type(newNode) == 'table' then
      container[key] = newNode
    end
    return action
  end)
end

local TOKEN_FIELDS = {'id', 'sourceString', 'sourcePath', 'token', 'line', 'position'}
function ast.clean(node)
  for _, field in ipairs(TOKEN_FIELDS) do
    node[field] = nil
  end
end

return ast
