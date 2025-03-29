local lcLib = require('luachild')

local ProcessHandle
local isWindowsOS = string.sub(package.config, 1, 1) == '\\'
if isWindowsOS then
  ProcessHandle = require('jls.lang.ProcessHandle-win32')
else
  ProcessHandle = require('jls.lang.ProcessHandle-linux')
end

local function getFdKey(key)
  return key == 'stdin' and 'readFd' or 'writeFd'
end

local function getPipeFd(processBuilder, key)
  local pipe = processBuilder[key]
  if type(pipe) == 'table' then
    if pipe.fd then
      return pipe.fd
    end
    local fd = pipe[getFdKey(key)]
    if fd and fd.fd then
      return fd.fd
    end
  end
end

local function closePipeFd(processBuilder, key)
  local pipe = processBuilder[key]
  if type(pipe) == 'table' then
    local fdKey = getFdKey(key)
    local fd = pipe[fdKey]
    if fd then
      fd:close()
      pipe[fdKey] = nil
    end
  end
end

ProcessHandle.build = function(processBuilder)
  local params = {}
  for _, v in ipairs(processBuilder.cmd) do
    table.insert(params, v)
  end
  if type(processBuilder.env) == 'table' then
    params.env = processBuilder.env
  end
  if processBuilder.dir then
    error('cannot set dir')
  end
  params.stdin = getPipeFd(processBuilder, 'stdin')
  params.stderr = getPipeFd(processBuilder, 'stderr')
  params.stdout = getPipeFd(processBuilder, 'stdout')
  local process, err = lcLib.spawn(params)
  closePipeFd(processBuilder, 'stdin')
  closePipeFd(processBuilder, 'stderr')
  closePipeFd(processBuilder, 'stdout')
  if not process then
    return nil, err
  end
  local spid, state = string.match(tostring(process), '^process%s*%((%d+),%s*(%a+)%)')
  -- state is "running" or "terminated"
  local pid = tonumber(spid)
  if pid and pid > 0 then
    local ph = ProcessHandle:new(pid)
    ph.process = process
    return ph
  end
  return nil, 'unable to parse pid'
end

return ProcessHandle
