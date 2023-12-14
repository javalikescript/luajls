--- Abstract Syntax Tree (AST) utility module.
-- This module allows to parse Lua into AST, manipulate AST and to generate Lua from AST.
--
-- The AST is represented using Lua table.
--
-- The types are: `assignment`, `binary`, `block`, `break`, `call`, `declaration`, `for`, `function`, `goto`, `identifier`, `if`, `label`, `literal`, `lookup`, `repeat`, `return`, `table`, `unary`, `vararg`, `while`
--
-- The operators are: `+`, `-`, `*`, `/`, `//`, `^`, `%`, `&`, `~`, `|`, `>>`, `<<`, `..`, `<`, `<=`, `>`, `>=`, `==`, `~=`, `and`, `or`, `-`, `not`, `#`, `~`
--
-- The table fields are: `adjustToOne`, `arguments`, `attribute`, `body`, `bodyFalse`, `bodyTrue`, `callee`, `condition`, `declaration`, `expression`, `fields`, `kind`, `label`, `left`, `member`, `method`, `name`, `names`, `object`, `operator`, `parameters`, `right`, `statements`, `targets`, `type`, `value`, `values`
--
-- @module jls.util.ast
-- @pragma nostrip

local dumbParser = require('dumbParser')

local ast = {}

local TOKEN_FIELDS = {'id', 'sourceString', 'sourcePath', 'token', 'line', 'position'}

local function cleanNode(node)
  for _, field in ipairs(TOKEN_FIELDS) do
    node[field] = nil
  end
end

--- Returns the AST representing the specified Lua code.
-- @tparam string lua the Lua code to parse.
-- @tparam[opt] boolean verbose whether or not to include extra information such as the line number.
-- @treturn table the AST representing the Lua.
function ast.parse(lua, verbose)
  local tree, err = dumbParser.parse(lua)
  if not tree or verbose then
    return tree, err
  end
  dumbParser.traverseTree(tree, cleanNode)
  return tree
end

--- Returns the AST representing the specified Lua expression.
-- @tparam string lua the Lua expression to parse.
-- @tparam[opt] boolean verbose whether or not to include extra information such as the line number.
-- @treturn table the AST representing the Lua.
function ast.parseExpression(lua, verbose)
  local tree, err = dumbParser.parseExpression(lua)
  if not tree or verbose then
    return tree, err
  end
  dumbParser.traverseTree(tree, cleanNode)
  return tree
end

--- Walks through the specified AST calling the callback function for each node.
-- The function is called with the AST node, if the return value is a table then it will replace the current AST node.
-- @tparam table tree the AST to walk through.
-- @tparam function callback the callback function, will be called with the node and the context.
-- @param[opt] context an optional context to pass to the callback function.
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
        ast.traverse(newNode, callback, context)
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

local function compatLookup(name, identifier)
  local id = identifier or 'compat'
  if id == '' then
    return {type = 'identifier', name = name}
  end
  local object = {type = 'identifier', name = id}
  return {
    type = 'lookup',
    object = object,
    member = {type = 'literal', value = name}
  }
end

local function checkCompat(compat, level)
  return compat and (not compat.level or compat.level <= level)
end

local function applyCompatMap(compatMap, node, level)
  local nodeType = node.type
  if nodeType == 'binary' then
    local compat = compatMap.binary[node.operator]
    if checkCompat(compat, level) then
      return {
        type = 'call',
        callee = compatLookup(compat.name, compat.identifier),
        arguments = {node.left, node.right}
      }
    end
  elseif nodeType == 'unary' then
    local compat = compatMap.unary[node.operator]
    if checkCompat(compat, level) then
      return {
        type = 'call',
        callee = compatLookup(compat.name, compat.identifier),
        arguments = {node.expression}
      }
    end
  elseif nodeType == 'lookup' and node.object.type == 'identifier' and node.member.type == 'literal' then
    local m = compatMap.lookup[node.object.name]
    if m then
      local compat = m[node.member.value]
      if compat then
        if checkCompat(compat, level) then
          return compatLookup(compat.name, compat.identifier)
        end
      else
        compat = m['*']
        if checkCompat(compat, level) then
          return compatLookup(node.member.value, compat.identifier)
        end
      end
    end
  elseif nodeType == 'call' and node.callee.type == 'identifier' then
    local compat = compatMap.call[node.callee.name]
    if checkCompat(compat, level) then
      return {
        type = 'call',
        callee = compatLookup(compat.name, compat.identifier),
        arguments = node.arguments
      }
    end
  end
end

local compatMap51 = {
  binary = {
    ['//'] = {name = 'fdiv'},
    ['&'] = {name = 'band'},
    ['|'] = {name = 'bor'},
    ['~'] = {name = 'bxor'},
    ['>>'] = {name = 'rshift'},
    ['<<'] = {name = 'lshift'},
  },
  unary = {
    ['#'] = {name = 'len', level = 3},
    ['~'] = {name = 'bnot'},
  },
  call = {
    load = {name = 'load', level = 3},
    rawlen = {name = 'rawlen', level = 2},
    warn = {name = 'notAvailable', level = 2},
    xpcall = {name = 'xpcall', level = 3},
  },
  lookup = {
    coroutine = {
      close = {name = 'ignored', level = 2},
      isyieldable = {name = 'notAvailable', level = 2},
    },
    debug = {
      getuservalue = {name = 'notAvailable', level = 2},
      setuservalue = {name = 'notAvailable', level = 2},
      traceback = {name = 'traceback', level = 3},
      upvalueid = {name = 'notAvailable', level = 2},
      upvaluejoin = {name = 'notAvailable', level = 2},
    },
    math = {
      mininteger = {name = 'mininteger', level = 2},
      maxinteger = {name = 'maxinteger', level = 2},
      random = {name = 'random', level = 3},
      tointeger = {name = 'tointeger', level = 2},
      type = {name = 'mathtype', level = 2},
      ult = {name = 'ult', level = 2},
    },
    os = {
      execute = {name = 'execute', level = 3},
    },
    package = {
      searchers = {name = 'notAvailable', level = 2},
      searchpath = {name = 'searchpath', level = 2},
    },
    string = {
      format = {name = 'format', level = 3},
      pack = {name = 'spack', level = 2},
      packsize = {name = 'spacksize', level = 2},
      unpack = {name = 'sunpack', level = 2},
    },
    table = {
      move = {name = 'tmove', level = 2},
      pack = {name = 'pack', level = 2},
      unpack = {name = 'unpack', level = 2},
    },
    utf8 = {
      char = {name = 'uchar', level = 2},
      charpattern = {name = 'notAvailable', level = 2},
      codepoint = {name = 'ucodepoint', level = 2},
      codes = {name = 'ucodes', level = 2},
    },
    _ENV = {
      ['*'] = {identifier = ''},
    },
  },
}

function ast.toLua51(node, level)
  -- for type block, we may want to add require compat
  return applyCompatMap(compatMap51, node, level or 10)
end

return ast
