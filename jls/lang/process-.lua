
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

return {
  execute = function(command, cb)
    local status, kind, code = os.execute(command)
    if status then
      cb()
    else
      cb({
        code = math.floor(code),
        kind = kind
      })
    end
  end,
  exePath = function()
    return exePath
  end,
  kill = function(pid)
    error('not available')
  end,
  spawn = function(pb)
    local line = ''
    for _, a in ipairs(pb.cmd) do
      line = line..' '..a
    end
    os.execute(line) -- will block
    return -1
  end
}
