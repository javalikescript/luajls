local sigarLib = require('sigar')

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local system = require('jls.lang.system')
local tables = require("jls.util.tables")


local function tables_add(st, t)
  if t then
    for k, v in pairs(t) do
      local sv = st[k] or 0
      st[k] = sv + v
    end
  end
  return st
end

local function tables_substract(st, t)
  if t then
    for k, v in pairs(t) do
      local sv = st[k] or 0
      st[k] = sv - v
    end
  end
  return st
end

local function tables_copy(st, t)
  if t then
    for k, v in pairs(t) do
      st[k] = v
    end
  end
  return st
end

local function tables_listToJson(list)
  local jsonList = {}
  for _, item in ipairs(list) do
    table.insert(jsonList, item:toJson())
  end
  return jsonList
end

local ROUND_FACTOR = 10

local function round(value)
  return math.floor(value * ROUND_FACTOR) / ROUND_FACTOR
end

local function percent(value, total)
  return round(value / total * 100)
end


local TOTAL_CORES = (function()
  local cpu = sigarLib.new():cpus()[1]
  if cpu then
    return cpu:info().total_cores
  end
  return 1
end)()

local SigarInfo = class.create(function(sigarInfo)

  function sigarInfo:initialize()
    self.at = system.currentTimeMillis()
  end

  function sigarInfo:getName()
    return ''
  end

  function sigarInfo:copy(si)
    self.at = si.at
    return self
  end

  function sigarInfo:clone()
    return self:getClass():new():copy(self)
  end

  function sigarInfo:substract(si)
    self.duration = self.at - si.at
    return self
  end

  function sigarInfo:newDelta(pi)
    return self:clone():substract(pi)
  end

  function sigarInfo:toJson()
    return {}
  end

end)

local ProcessInfo = class.create(SigarInfo, function(processInfo, super)

  function processInfo:initialize(exe, mem, time, state)
    super.initialize(self)
    -- name, cwd, root
    self.exe = exe
    -- mem: page_faults, size, resident
    self.mem = mem
    -- time: start_time, total, user, sys
    self.time = time
    -- state: priority, threads, ppid
    self.state = state
  end

  function processInfo:getName()
    return self.exe.name
  end

  function processInfo:toJson()
    return {
      exe = self.exe,
      mem = self.mem,
      time = self.time,
      state = self.state
    }
  end

  function processInfo:copy(pi)
    super.copy(self, pi)
    self.exe = tables_copy({}, pi.exe)
    self.mem = tables_copy({}, pi.mem)
    self.time = tables_copy({}, pi.time)
    self.state = tables_copy({}, pi.state)
    return self
  end

  function processInfo:substract(pi)
    super.substract(self, pi)
    tables_substract(self.mem, pi.mem)
    tables_substract(self.time, pi.time)
    return self
  end

  function processInfo:getWorkDir()
    return self.exe.cwd
  end

  function processInfo:getStartTime()
    return self.time.start_time
  end

  function processInfo:getDuration()
    return self.duration or self.time.start_time - self.at
  end

  function processInfo:getTotalTime()
    return self:getDuration() * TOTAL_CORES
  end

  function processInfo:getUserPercent()
    return percent(self.time.user, self:getTotalTime())
  end

  function processInfo:getSystemPercent()
    return percent(self.time.sys, self:getTotalTime())
  end

  function processInfo:getIdlePercent()
    return 100 - self:getUsagePercent()
  end

  function processInfo:getUsagePercent()
    return percent(self.time.total, self:getTotalTime())
  end

  function processInfo:getMemorySize()
    return self.mem.size
  end

  function processInfo:getMemoryResident()
    return self.mem.resident
  end

  function processInfo:getPid()
    return self.pid
  end

  function processInfo:getParentPid()
    return self.state.ppid
  end

end)

function ProcessInfo.fromProc(proc)
  return ProcessInfo:new(proc:exe(), proc:mem(), proc:time(), proc:state())
end


local FileSystemInfo = class.create(SigarInfo, function(fileSystemInfo, super)

  function fileSystemInfo:initialize(fs)
    super.initialize(self)
    self.info = fs:info()
    self.usage = fs:usage()
  end

  function fileSystemInfo:getName()
    return self.info.dir_name
  end

  function fileSystemInfo:toJson()
    return {
      info = self.info,
      usage = self.usage
    }
  end

  function fileSystemInfo:getUsagePercent()
    return percent(self.usage.used, self.usage.total)
  end

  function fileSystemInfo:isLocal()
    return self.info.type_name == 'local'
  end

end)

local MemoryInfo = class.create(SigarInfo, function(memoryInfo, super)

  function memoryInfo:initialize(mem, swap)
    super.initialize(self)
    -- used, free_percent, free, actual_used, actual_free, used_percent, ram, total
    self.mem = mem
    self.swap = swap
  end

  function memoryInfo:getName()
    return 'Memory'
  end

  function memoryInfo:toJson()
    return {
      mem = self.mem,
      swap = self.swap
    }
  end

  function memoryInfo:getTotalSize()
    return self.mem.total
  end

  function memoryInfo:getUsedPercent()
    return round(self.mem.used_percent)
  end

end)

local ProcessorData = class.create(SigarInfo, function(processorData, super)

  function processorData:initialize(data)
    super.initialize(self)
    -- idle, stolen, irq, total, user, wait, sys, nice, soft_irq
    self.data = data
  end

  function processorData:getUserPercent()
    return percent(self.data.user, self.data.total)
  end

  function processorData:getSystemPercent()
    return percent(self.data.sys, self.data.total)
  end

  function processorData:getIdlePercent()
    return percent(self.data.idle, self.data.total)
  end

  function processorData:getUsagePercent()
    return 100 - self:getIdlePercent()
  end

  function processorData:copy(si)
    super.copy(self, si)
    self.data = tables_copy({}, si.data)
    return self
  end

  function processorData:substract(si)
    super.substract(self, si)
    tables_substract(self.data, si.data)
    return self
  end

end)

local ProcessorInfo = class.create(ProcessorData, function(processorInfo, super)

  function processorInfo:initialize(data, info, list)
    super.initialize(self, data)
    -- total_cores, mhz, cores_per_socket, vendor, model, total_sockets
    self.info = info
    self.list = list
  end

  function processorInfo:getName()
    if self.info then
      return self.info.model
    end
    return 'Processor'
  end

  function processorInfo:toJson()
    return {
      data = self.data,
      info = self.info,
      list = self.list and tables_listToJson(self.list)
    }
  end

  function processorInfo:list()
    return self.list
  end

end)

function ProcessorInfo.fromCPUs(cpus)
  local list = {}
  local data = {}
  local info = {}
  --for _, cpu in pairs(cpus) do
  for i = 1, #cpus do
    local cpu = cpus[i]
    local d = cpu:data()
    local i = cpu:info()
    if not info then
      info = i
    end
    tables_add(data, d)
    table.insert(list, ProcessorInfo:new(d, i))
  end
  return ProcessorInfo:new(data, info, list)
end


local DiskInfo = class.create(SigarInfo, function(diskInfo, super)

  function diskInfo:initialize(name, usage)
    super.initialize(self)
    -- name, usage
    self.name = name
    -- rtime, qtime, service_time, queue, reads, time, read_bytes, write_bytes, wtime, snaptime, writes
    self.usage = usage
  end

  function diskInfo:getName()
    return self.name
  end

  function diskInfo:toJson()
    return {
      name = self.name,
      usage = self.usage
    }
  end
end)

local SystemInfo = class.create(SigarInfo, function(systemInfo, super)

  function systemInfo:initialize(sysinfo)
    super.initialize(self)
    -- machine, vendor_code_name, description, name, vendor_name, vendor, patch_level, vendor_version, arch, version
    self.sysinfo = sysinfo
  end

  function systemInfo:getName()
    return self.sysinfo.description
  end

  function systemInfo:toJson()
    return self.sysinfo
  end
end)

return class.create(SigarInfo, function(sigar, super)

  function sigar:initialize()
    super.initialize(self)
    -- cpus, procs, filesystems, disks, disk, who, netifs, proc, pid, mem, swap, version, sysinfo
    self.sigar = sigarLib.new()
  end

  function sigar:getProcessInfo(pid)
    if not pid then
      pid = self.sigar:pid()
    end
    return ProcessInfo.fromProc(self.sigar:proc(pid))
  end

  function sigar:getProcessIds()
    return self.sigar:procs()
  end

  function sigar:getMemoryInfo()
    return MemoryInfo:new(self.sigar:mem(), self.sigar:swap())
  end

  function sigar:getProcessorInfo()
    return ProcessorInfo.fromCPUs(self.sigar:cpus())
  end

  function sigar:getFileSystemInfos()
    local infos = {}
    --for _, fs in pairs(self.sigar:filesystems()) do
    local fses = self.sigar:filesystems()
    for i = 1, #fses do
      local fs = fses[i]
      table.insert(infos, FileSystemInfo:new(fs))
    end
    return infos
  end

  function sigar:getDiskInfo(name)
    local disk = self.sigar:disk(name)
    local usage = disk:usage()
    if usage then
      return DiskInfo:new(disk:name(), usage)
    end
  end

  function sigar:getDiskInfos()
    local infos = {}
    --for _, disk in pairs(self.sigar:disks()) do
    local disks = self.sigar:disks()
    for i = 1, #disks do
      local disk = disks[i]
      table.insert(infos, DiskInfo:new(disk:name(), disk:usage()))
    end
    return infos
  end

  function sigar:getSystemInfo()
    return SystemInfo:new(self.sigar:sysinfo())
  end

  function sigar:toJson()
    return {
      at = self.at,
      proc = self:getProcessInfo():toJson(),
      cpu = self:getProcessorInfo():toJson(),
      mem = self:getMemoryInfo():toJson(),
      filesystems = tables_listToJson(self:getFileSystemInfos()),
      disks = tables_listToJson(self:getDiskInfos()),
      sysinfo = self:getSystemInfo():toJson()
    }
  end

end)
