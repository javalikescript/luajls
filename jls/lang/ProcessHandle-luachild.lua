local lcLib = require('luachild')

local ProcessHandle
local isWindowsOS = string.sub(package.config, 1, 1) == '\\'
if isWindowsOS then
  ProcessHandle = require('jls.lang.ProcessHandle-win32')
else
  ProcessHandle = require('jls.lang.ProcessHandle-linux')
end

local function getPipeFd(processBuilder, key)
  local fd = nil
  local pipe = processBuilder[key]
  if type(pipe) == 'table' then
    if pipe.fd then
      fd = pipe.fd
    elseif key == 'stdin' then
      if pipe.readFd then
        fd = pipe.readFd
      end
    elseif pipe.writeFd then
      fd = pipe.writeFd
    end
  end
  return fd
end

local function closePipeFd(processBuilder, key)
  local pipe = processBuilder[key]
  if type(pipe) == 'table' then
    if key == 'stdin' then
      if pipe.readFd then
        pipe.readFd:close()
        pipe.readFd = nil
      end
    elseif pipe.writeFd then
      pipe.writeFd:close()
      pipe.writeFd = nil
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
