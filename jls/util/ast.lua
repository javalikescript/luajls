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

local TOKEN_FIELDS = {'id', 'sourceString', 'sourcePath', 'token', 'line', 'position'}

function ast.clean(node)
  for _, field in ipairs(TOKEN_FIELDS) do
    node[field] = nil
  end
end

--- Walks through the specified AST calling the callback function for each node.
-- The function is called with the AST node, if the return value is a table then it will replace the current AST node.
-- @tparam table tree the AST to walk through.
-- @tparam function callback the callback function.
-- @treturn table the AST.
function ast.traverse(tree, callback, context)
  local updated = false
  local function fn(node, parent, container, key)
    local action, newNode = callback(node, context)
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

--- Returns the AST representing the specified Lua code.
-- @tparam string lua the Lua code to parse.
-- @treturn table the AST representing the Lua.
function ast.parse(lua, verbose)
  local tree = dumbParser.parse(lua)
  if verbose then
    return tree
  end
  return ast.traverse(tree, ast.clean)
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

function ast.hasLiteral(tree, name)
  local found = false
  dumbParser.traverseTree(tree, function(node)
    if node.type == 'literal' and node.value == name then
      found = true
      return 'stop'
    end
  end)
  return found
end

local function compatLookup(name, identifier, useRequire)
  local object
  if useRequire then
    object = {
      type = 'call',
      callee = {type = 'identifier', name = 'require'},
      arguments = {{type = 'literal', value = 'jls.util.compat'}},
    }
  else
    object = {type = 'identifier', name = identifier or 'compat'}
  end
  return {
    type = 'lookup',
    object = object,
    member = {type = 'literal', value = name}
  }
end

local function applyCompatMap(compatMap, node, level)
  local nodeType = node.type
  if nodeType == 'binary' then
    local compat = compatMap.binary[node.operator]
    if compat and compat.level <= level then
      return {
        type = 'call',
        callee = compatLookup(compat.name),
        arguments = {node.left, node.right}
      }
    end
  elseif nodeType == 'unary' then
    local compat = compatMap.unary[node.operator]
    if compat and compat.level <= level then
      return {
        type = 'call',
        callee = compatLookup(compat.name),
        arguments = {node.expression}
      }
    end
  elseif nodeType == 'lookup' and node.object.type == 'identifier' and node.member.type == 'literal' then
    local m = compatMap.lookup[node.object.name]
    if m then
      local compat = m[node.member.value]
      if compat and compat.level <= level then
        return compatLookup(compat.name)
      end
    end
  elseif nodeType == 'call' and node.callee.type == 'identifier' then
    local compat = compatMap.call[node.callee.name]
    if compat and compat.level <= level then
      return {
        type = 'call',
        callee = compatLookup(compat.name),
        arguments = node.arguments
      }
    end
  end
end

local compatMap51 = {
  binary = {
    ['//'] = {level = 1, name = 'fdiv'},
    ['&'] = {level = 1, name = 'band'},
    ['|'] = {level = 1, name = 'bor'},
    ['~'] = {level = 1, name = 'bxor'},
    ['>>'] = {level = 1, name = 'rshift'},
    ['<<'] = {level = 1, name = 'lshift'},
  },
  unary = {
    ['#'] = {level = 3, name = 'len'},
    ['~'] = {level = 1, name = 'bnot'},
  },
  call = {
    load = {level = 3, name = 'load'},
    rawlen = {level = 2, name = 'rawlen'},
    warn = {level = 2, name = 'notAvailable'},
    xpcall = {level = 3, name = 'xpcall'},
  },
  lookup = {
    coroutine = {
      close = {level = 2, name = 'notAvailable'},
      isyieldable = {level = 2, name = 'notAvailable'},
    },
    debug = {
      getuservalue = {level = 2, name = 'notAvailable'},
      setuservalue = {level = 2, name = 'notAvailable'},
      traceback = {level = 3, name = 'traceback'},
      upvalueid = {level = 2, name = 'notAvailable'},
      upvaluejoin = {level = 2, name = 'notAvailable'},
    },
    math = {
      mininteger = {level = 2, name = 'mininteger'},
      maxinteger = {level = 2, name = 'maxinteger'},
      random = {level = 3, name = 'random'},
      tointeger = {level = 2, name = 'tointeger'},
      type = {level = 2, name = 'mathtype'},
      ult = {level = 2, name = 'ult'},
    },
    package = {
      searchers = {level = 2, name = 'notAvailable'},
      searchpath = {level = 2, name = 'searchpath'},
    },
    string = {
      format = {level = 3, name = 'format'},
      pack = {level = 2, name = 'spack'},
      packsize = {level = 2, name = 'spacksize'},
      unpack = {level = 2, name = 'sunpack'},
    },
    table = {
      move = {level = 2, name = 'tmove'},
      pack = {level = 2, name = 'pack'},
      unpack = {level = 2, name = 'unpack'},
    },
    utf8 = {
      char = {level = 2, name = 'uchar'},
      charpattern = {level = 2, name = 'notAvailable'},
      codepoint = {level = 2, name = 'ucodepoint'},
      codes = {level = 2, name = 'ucodes'},
    },
  },
}

function ast.toLua51(node, level)
  -- for type block, we may want to require compat
  return applyCompatMap(compatMap51, node, level or 10)
end

return ast
