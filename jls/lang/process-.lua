
local exePath = 'lua' -- fallback
-- look for the lua path in the arguments
if arg then
  for i = 0, -10, -1 do
    if arg[i] then
      exePath = arg[i]
    else
      break
    end
  end
end

local formatCommandLine = require('jls.lang.formatCommandLine')

return {
  exePath = function()
    return exePath
  end,
  getPid = function()
    error('not available')
  end,
  kill = function(pid)
    error('not available')
  end,
  spawn = function(pb, onexit)
    if pb.stdin or pb.stdout or pb.stderr then
      -- TODO use popen
      error('cannot redirect')
    end
    local line = formatCommandLine(pb.cmd)
    local status, kind, code = os.execute(line) -- will block
    if type(onexit) == 'function' then
      onexit(code or 0)
    end
    return -1
  end
}
