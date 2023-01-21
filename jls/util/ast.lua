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
  local updated = false
  local function fn(node, parent, container, key)
    local action, newNode = callback(node)
    if type(action) == 'table' then
      newNode = action
      action = nil
    end
    if type(newNode) == 'table' then
      container[key] = newNode
      updated = true
      if action == nil then
        ast.traverse(newNode, callback)
        if dumbParser.traverseTree(newNode, fn) then
          return 'stop'
        end
      end
      return 'ignorechildren'
    end
    return action
  end
  local stopped = dumbParser.traverseTree(tree, fn)
  return tree, updated, stopped
end

local TOKEN_FIELDS = {'id', 'sourceString', 'sourcePath', 'token', 'line', 'position'}
function ast.clean(node)
  for _, field in ipairs(TOKEN_FIELDS) do
    node[field] = nil
  end
end

local function compatLookup(name, identifier)
  return {
    type = 'lookup',
    object = {type = 'identifier', name = identifier or 'compat'},
    member = {type = 'literal', value = name}
  }
end

local function applyCompatMap(compatMap, node)
  local nodeType = node.type
  if nodeType == 'binary' then
    local name = compatMap.binary[node.operator]
    if name then
      return {
        type = 'call',
        callee = compatLookup(name),
        arguments = {node.left, node.right}
      }
    end
  elseif nodeType == 'unary' then
    local name = compatMap.unary[node.operator]
    if name then
      return {
        type = 'call',
        callee = compatLookup(name),
        arguments = {node.expression}
      }
    end
  elseif nodeType == 'lookup' and node.object.type == 'identifier' and node.member.type == 'literal' then
    local m = compatMap.lookup[node.object.name]
    if m then
      local name = m[node.member.value]
      if name then
        return compatLookup(name)
      end
    end
  end
end

local compatMap51 = {
  binary = {
    ['//']= 'fdiv',
    ['&'] = 'band',
    ['|'] = 'bor',
    ['~'] = 'bxor',
    ['>>']= 'rshift',
    ['<<']= 'lshift',
  },
  unary = {
    ['#'] = 'len',
    ['~'] = 'bnot',
  },
  call = {
    -- warn
    rawlen = 'rawlen',
  },
  lookup = {
    -- coroutine: close, isyieldable
    -- debug: getuservalue, setuservalue, upvalueid, upvaluejoin
    math = {
      tointeger = 'tointeger',
      mininteger = 'mininteger',
      maxinteger = 'maxinteger',
      type = 'mathtype',
      ult = 'ult',
    },
    package = {
      -- searchers
      searchpath = 'searchpath',
    },
    string = {
      format = 'format',
      pack = 'spack',
      packsize = 'spacksize',
      unpack = 'sunpack',
    },
    table = {
      move = 'tmove',
      pack = 'pack',
      unpack = 'unpack',
    },
    utf8 = {
      -- charpattern
      char = 'uchar',
      codepoint = 'ucodepoint',
      codes = 'ucodes',
    },
  },
}

function ast.toLua51(node)
  return applyCompatMap(compatMap51, node)
end

return ast
