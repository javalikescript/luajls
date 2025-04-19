local lcLib = require('luachild')
local loader = require('jls.lang.loader')

local ProcessHandle
local isWindowsOS = string.sub(package.config, 1, 1) == '\\'
if isWindowsOS then
  ProcessHandle = loader.tryRequire('jls.lang.ProcessHandle-win32')
else
  ProcessHandle = loader.tryRequire('jls.lang.ProcessHandle-linux')
end

local function parsePid(process)
  local spid, state = string.match(tostring(process), '^process%s*%((%d+),%s*(%a+)%)')
  local pid = tonumber(spid)
  if pid and pid > 0 then
    return pid, state
  end
  return nil, 'unable to parse pid'
end

if not ProcessHandle then
  local Promise = require('jls.lang.Promise')
  local event = loader.requireOne('jls.lang.event-')

  ProcessHandle = require('jls.lang.class').create('jls.lang.ProcessHandleBase', function(processHandle, super)
    function processHandle:ended()
      if not self.endPromise then
        self.endPromise = Promise:new(function(resolve, reject)
          event:setTask(function()
            if self:isAlive() then
              return true
            end
            local code, err = lcLib.wait(self.process)
            if code then
              self.code = code
              resolve(code)
            else
              reject(err)
            end
            return false
          end)
        end)
      end
      return self.endPromise
    end
  end)
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
  local pid, state = parsePid(process)
  if pid then
    local ph = ProcessHandle:new(pid)
    ph.process = process
    return ph
  end
  return nil, state
end

return ProcessHandle
