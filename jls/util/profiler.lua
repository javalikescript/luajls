-- Provide performance measurement functions.
-- @module jls.util.profiler

local logger = require('jls.lang.logger')
local File = require('jls.io.File')
local FileDescriptor = require('jls.io.FileDescriptor')

local lmprofLib = require('lmprof')

local profiler = {}

function profiler.start(filename)
  lmprofLib.start(filename);
  logger:fine('Profiling started')
end

function profiler.stop(filename)
  lmprofLib.stop(filename);
  logger:fine('Profiling stopped')
end

function profiler.profileCall(fn, filename)
  lmprofLib.start(filename);
  local results = table.pack(pcall(fn))
  lmprofLib.stop(filename);
  return table.unpack(results)
end

function profiler.visitAll(visit, rootTable, maxLevel)
  local seen = {}
  local visitTable
  visitTable = function(t, l)
    if seen[t] then return end
    visit(t, l)
    l = l + 1
    if maxLevel and l > maxLevel then return end
    seen[t] = true
    for k, v in pairs(t) do
      if type(v) == "table" then
        visitTable(v, l)
      elseif type(v) == "userdata" then
        visit(v, l)
      end
    end
  end
  visitTable(rootTable or _G, 0)
end

function profiler.visitRegistry(visit)
  return profiler.visitAll(visit, debug.getregistry())
end

function profiler.countAllByType(rootTable)
	local counts = {}
	profiler.visitAll(function(o, l)
		local t = type_name(o)
		counts[t] = (counts[t] or 0) + 1
	end, rootTable)
	local count = 0
  for _, c in pairs(counts) do
    count = count + c
  end
  return counts, count
end

function profiler.loadMemoryMapsFromFile(file)
  local lines = file:readAllLines()
  local maps = {}
  for _, line in ipairs(lines) do
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('line "'..tostring(line)..'"')
    end
    local startHex, stopHex = string.match(line, '^([0-9a-fA-F]+)-([0-9a-fA-F]+) ')
    if startHex and stopHex then
      local start = tonumber(startHex, 16)
      local stop = tonumber(stopHex, 16)
      if logger:isLoggable(logger.DEBUG) then
        logger:debug('map '..tostring(start)..'-'..tostring(stop)..' ('..tostring(stop - start)..')')
      end
      table.insert(maps, {
        offset = start,
        size = stop - start,
        endOffset = stop
      })
    end
  end
  return maps
end

local monLib = require('jls.lang.loader').tryRequire('mon')

if monLib then
  function profiler.dumpMemory(pid)
    local mapsFile = File:new('/proc/'..tostring(pid)..'/maps')
    local maps = profiler.loadMemoryMapsFromFile(mapsFile)
    --local dumpFd, err = FileDescriptor.openSync(tostring(pid)..'.core', 'w')
    monLib.ptrace(16, pid) -- PTRACE_ATTACH
    monLib.wait()
    local memFd, err = FileDescriptor.openSync('/proc/'..tostring(pid)..'/mem', 'r')
    if not memFd then
      return nil, err
    end
    for _, map in ipairs(maps) do
      if map.size > 0 then
        local content = memFd:readSync(map.size, map.offset)
        --dumpFd:writeSync(content)
        if content then
          io.write(content)
        end
      end
    end
    memFd:closeSync()
    monLib.ptrace(7, pid) -- PTRACE_CONT
    monLib.ptrace(17, pid) -- PTRACE_DETACH
  end
end

return profiler