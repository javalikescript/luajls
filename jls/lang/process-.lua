
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

local isWindowsOS = string.sub(package.config, 1, 1) == '\\' or string.find(package.cpath, '%.dll')

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
    local line
    if isWindowsOS then
      line = pb.cmd[1]..' "'..table.concat(pb.cmd, '" "', 2)..'"'
    else
      line = '"'..table.concat(pb.cmd, '" "')..'"'
    end
    local status, kind, code = os.execute(line) -- will block
    if type(onexit) == 'function' then
      onexit(code or 0)
    end
    return -1
  end
}
