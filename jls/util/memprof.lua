--[[
This module helps to gather information on memory usage.

You could trigger memory profiling using the environment variable
JLS_MEMORY_PROFILING and loading the module.

export JLS_MEMORY_PROFILING=every:5
lua -l jls.util.memprof examples/httpServer.lua
]]

local buffer, class, Map, List
do
  local status
  status, buffer = pcall(require, 'buffer')
  if not status then
    buffer = {
      len = function(u)
        return 0
      end
    }
  end
  status, class = pcall(require, 'jls.lang.class')
  if not status then
    class = {
      getClass = function(c)
        return nil
      end
    }
  end
  status, Map = pcall(require, 'jls.util.Map')
  if not status then
    Map = {
      compareKey = function(a, b)
        return tostring(a) < tostring(b)
      end,
      keys = function(t)
        local l = {}; for k in pairs(t) do table.insert(t, k); end; return l
      end,
      assign = function(tt, st)
        for k, v in pairs(st) do tt[k] = v; end; return tt
      end
    }
  end
  status, List = pcall(require, 'jls.util.List')
  if not status then
    List = {
      indexOf = function(l, v)
        for i, w in ipairs(l) do if w == v then return i; end; end; return 0
      end,
      concat = function(...)
        local tl = {}; for _, l in ipairs({...}) do; for _, v in ipairs(l) do table.insert(tl, v); end; end; return tl
      end,
      filter = function(l, fn)
        local f = {}; for _, v in ipairs(l) do if fn(v) then table.insert(f, v); end; end; return f
      end
    }
  end
end

local LUA_TYPES = {
  'boolean', 'number', 'string', 'function', 'userdata', 'thread', 'table'
}
local LUA_FUNCTIONS = {
  'assert', 'collectgarbage', 'dofile', 'error', 'getmetatable', 'ipairs',
  'load', 'loadfile', 'next', 'pairs', 'pcall', 'print', 'rawequal', 'rawget', 'rawlen',
  'rawset', 'require', 'select', 'setmetatable', 'tonumber', 'tostring', 'type', 'warn', 'xpcall'
}
local LUA_PACKAGES = {
  '_G', 'coroutine', 'debug', 'io', 'math', 'os', 'package', 'string', 'table', 'utf8'
}
local LUA_REGISTRY_NAMES = {
  'FILE*', '_CLIBS', '_LOADED', '_PRELOAD', '_IO_input', '_IO_output'
}
local LUA_GLOBALS = List.concat({'_G', '_VERSION', 'arg'}, LUA_FUNCTIONS, LUA_PACKAGES)
local LUA_SIZE_T_LEN = string.len(string.pack('T', 0))
local LUA_NUMBER_LEN = string.len(string.pack('n', 0))

local function compareBySize(a, b)
  return a.size > b.size
end

local function filtermap(t, fn)
  local f = {}
  for k, v in pairs(t) do
    if fn(k, v) then
      f[k] = v
    end
  end
  return f
end
local function filterIn(t, lvl)
  return filtermap(t, function(k)
    return List.indexOf(lvl, k) > 0
  end)
end
local function filterNotIn(t, lvl)
  return filtermap(t, function(k)
    return List.indexOf(lvl, k) == 0
  end)
end
local function filterNotNumber(t)
  return filtermap(t, function(k)
    return type(k) ~= 'number'
  end)
end

local function filterListNotIn(l, lvl)
  return List.filter(l, function(v)
    return List.indexOf(lvl, v) == 0
  end)
end

local function joinList(l, sep)
  local sl = {}
  for _, v in ipairs(l) do
    table.insert(sl, tostring(v))
  end
  table.sort(sl)
  return table.concat(sl, sep or ' ')
end

local function head(s, d, n)
  table.move(s, 1, n or 5, 1, d)
end

local function sumMapValues(t)
  local s = 0
  for _, v in pairs(t) do
    if type(v) == 'number' then
      s = s + v
    end
  end
  return s
end
local function sumKey(t, n)
  local s = 0
  for _, st in pairs(t) do
    local v = st[n]
    if type(v) == 'number' then
      s = s + v
    end
  end
  return s
end
local function sumKeys(t)
  local s = {}
  local _, m = next(t)
  for n in pairs(m) do
    s[n] = sumKey(t, n)
  end
  return s
end

local function len(o)
  local to = type(o)
  if to == 'string' then
    return string.len(o)
  elseif to == 'function' then
    local status, chunk = pcall(string.dump, o)
    if status then
      return string.len(chunk)
    end
  elseif to == 'userdata' then
    return buffer.len(o)
  elseif to == 'number' then
    return LUA_NUMBER_LEN
  elseif to == 'boolean' then
    return 1
  end
  return 0
end

local function visitObject(gr, lr, o, n, r)
  if o == nil then
    return 0
  end
  local ro = gr[o]
  if ro == nil then
    ro = lr[o]
  end
  local name
  if type(n) == 'string' and n ~= '' and n ~= '?'  then
    name = n
  end
  if ro ~= nil then
    ro.refs = ro.refs + 1
    if name and List.indexOf(ro.names, name) == 0 then
      table.insert(ro.names, name)
    end
    return ro.sub_size + ro.size
  end
  ro = {
    names = {},
    size = 0,
    sub_size = 0,
    refs = 1,
  }
  if name then
    table.insert(ro.names, name)
  end
  lr[o] = ro
  local s, ss = 0, 0
  if r then
    local to = type(o)
    if to == 'function' then
      for i = 1, 256 do
        local nn, v = debug.getupvalue(o, i)
        if nn then
          s = s + 1
          ss = ss + visitObject(gr, lr, v, nn, r)
        else
          break
        end
      end
    elseif to == 'table' then
      for k, v in pairs(o) do
        s = s + 2
        ss = ss + visitObject(gr, lr, k, nil, r)
        ss = ss + visitObject(gr, lr, v, k, r)
      end
      --local mt = getmetatable(o)
    end
  end
  ro.size = s
  ro.sub_size = ss
  return s + ss
end

local function createReport(registry, gr)
  local registryByType = {}
  for _, t in ipairs(LUA_TYPES) do
    registryByType[t] = {}
  end
  for o, v in pairs(registry) do
    registryByType[type(o)][o] = v
  end
  local reportByType = {}
  for _, t in ipairs(LUA_TYPES) do
    local c = 0
    local refs = 0
    local s = 0
    for o, ro in pairs(registryByType[t]) do
      c = c + 1
      refs = refs + ro.refs
      s = s + len(o) + ro.size * LUA_SIZE_T_LEN
    end
    reportByType[t] = {
      count = c,
      refs = refs,
      size = s,
    }
  end
  local classMap = {}
  local tables = {}
  for o, ro in pairs(registryByType.table) do
    local c = class.getClass(o)
    local cro = c and (registry[c] or (gr and gr[c]))
    if cro then
      local ci = classMap[c]
      if ci then
        ci.size = ci.size + 1
      else
        classMap[c] = {
          names = cro.names,
          size = 1,
        }
      end
    else
      table.insert(tables, {
        names = joinList(ro.names),
        size = ro.size,
      })
    end
  end
  table.sort(tables, compareBySize)
  local top_tables = {}
  head(tables, top_tables)

  local classes = {}
  for _, ci in pairs(classMap) do
    table.insert(classes, {
      names = joinList(filterListNotIn(ci.names, {'class', 'super', '__index'})),
      size = ci.size,
    })
  end
  table.sort(classes, compareBySize)
  local top_classes = {}
  head(classes, top_classes)

  reportByType.all = sumKeys(reportByType)
  return {
    type = reportByType,
    top = {
      classes = top_classes,
      tables = top_tables,
    },
  }
end

local function visitTableValues(m, lm, t, r)
  local names = {}
  local ss = 0
  for k, v in pairs(t) do
    table.insert(names, k)
    ss = ss + visitObject(m, lm, v, k, r)
  end
  return names, ss
end

local function createReportForTableValues(m, t)
  local lm = {}
  local names, ss = visitTableValues(m, lm, t, true)
  local report = createReport(lm, m)
  Map.assign(m, lm)
  report.names = names
  report.size = #names
  report.sub_size = ss
  return report
end

local function getlocals(level)
  local locals = {}
  for i = 1, 256 do
    local k, v = debug.getlocal(level, i)
    if not k then
      break
    end
    locals[k] = v
  end
  return locals
end

local function getStackLocals(level)
  local locals = {}
  local lvl = level or 2
  while true do
    local info = debug.getinfo(lvl, 'nS')
    if not info or info.what == 'main' then
      break
    end
    --print('stack #'..tostring(lvl)..':', require('jls.util.json').stringify(info, '  '))
    for k, v in pairs(getlocals(lvl)) do
      local n = tostring(k)
      if locals[n] ~= nil then
        n = n..'('..tostring(lvl)..')'
      end
      locals[n] = v
    end
    lvl = lvl + 1
  end
  return locals
end

local function getMainLocals(level)
  local toplevel = level or 2
  while true do
    local info = debug.getinfo(toplevel + 1, 'nS')
    if not info then
      break
    end
    --print('level '..tostring(toplevel)..':', require('jls.util.json').stringify(info, '  '))
    toplevel = toplevel + 1
    if info.what == 'main' then
      break
    end
  end
  return getlocals(toplevel)
end

local memprof = {}

local function printTableRecursiveCSV(lines, keys, t, p)
  local sp = p and (p..'.') or ''
  local sks = {}
  for k in pairs(t) do
    table.insert(sks, k)
  end
  table.sort(sks, Map.compareKey)
  for _, k in ipairs(sks) do
    local v = t[k]
    if type(v) == 'table' then
      printTableRecursiveCSV(lines, keys, v, sp..k)
    end
  end
  local count = 0
  local values = {}
  for _, k in ipairs(keys) do
    local v = t[k]
    if v ~= nil then
      count = count + 1
    end
    table.insert(values, tostring(v))
  end
  if count > 0 and count == #keys and count == #sks then
    table.insert(lines, p..','..table.concat(values, ','))
  end
end

local function printTableCSV(lines, t, keys, name)
  table.insert(lines, (name or 'path')..','..table.concat(keys, ','))
  printTableRecursiveCSV(lines, keys, t)
end

function memprof.createReport(withDetails)
  local gcCountBefore = math.floor(collectgarbage('count') * 1024)
  local registry = {}
  visitObject(registry, registry, memprof, nil, false)
  visitTableValues(registry, registry, filterIn(_G, LUA_GLOBALS), false)
  -- TODO stack local
  local details = {
    a_registry = createReportForTableValues(registry, filterNotNumber(filterNotIn(debug.getregistry(), LUA_REGISTRY_NAMES))),
    b_packages = createReportForTableValues(registry, filterNotIn(package.loaded, LUA_PACKAGES)),
    c_globals = createReportForTableValues(registry, filterNotIn(_G, LUA_GLOBALS)),
    d_locals = createReportForTableValues(registry, getMainLocals(3)),
    --e_stacks = createReportForTableValues(registry, getStackLocals(3)),
  }
  return {
    date = os.date('%Y-%m-%dT%H:%M:%S'),
    all = createReport(registry),
    details = withDetails == true and details or nil,
    gc = {
      count = gcCountBefore,
    },
  }
end

function memprof.printReport(write, withGc, withDetails, format)
  if withGc == true then
    collectgarbage('collect')
  end
  local report = memprof.createReport(withDetails)
  local data
  if format == 'json' then
    data = require('jls.util.json').stringify(report, '  ')
  elseif format == 'lua' then
    data = require('jls.util.tables').stringify(report, '  ')
  elseif format == 'csv' or format == nil then
    local lines = {}
    table.insert(lines, 'date,'..report.date)
    printTableCSV(lines, report, {'count'})
    printTableCSV(lines, report, {'count', 'size', 'refs'})
    printTableCSV(lines, report, {'size', 'names'})
    table.insert(lines, '')
    data = table.concat(lines, '\n')
    lines = nil
  else
    error('Invalid format "'..tostring(format)..'"')
  end
  write = write or io.write
  write(data..'\n')
  report = nil
  data = nil
  if withGc == true then
    collectgarbage('collect')
  end
end

local memoryProfiling = os.getenv('JLS_MEMORY_PROFILING')
if memoryProfiling and memoryProfiling ~= '' then
  local logger = require('jls.lang.logger')
  logger:warn('memory profiling activated using "'..memoryProfiling..'"')
  local withGc = false
  local write = io.write
  for k, v in string.gmatch(memoryProfiling, "([^,:=]+)[:=]?([^,]*)") do
    local lk = string.lower(k)
    if lk == 'every' and v then
      local event = require('jls.lang.event')
      local timer = event:setInterval(function()
        memprof.printReport(write, withGc, false)
      end, math.floor(tonumber(v) * 1000))
      event:daemon(timer, true)
    elseif lk == 'detailsevery' and v then
      local event = require('jls.lang.event')
      local timer = event:setInterval(function()
        memprof.printReport(write, withGc, true)
      end, math.floor(tonumber(v) * 1000))
      event:daemon(timer, true)
    elseif lk == 'shutdown' then
      local runtime = require('jls.lang.runtime')
      runtime.addShutdownHook(function()
        memprof.printReport(write, true, true)
      end)
    elseif lk == 'gc' then
      withGc = true
    elseif lk == 'file' then
      local filename = v or 'memprof.log'
      write = function(data)
        local file = io.open(filename, 'ab')
        if file then
          file:write(data)
          file:close()
        end
      end
    else
      logger:warn('unknown memory profiling option "'..k..'"')
    end
  end
end

return memprof
