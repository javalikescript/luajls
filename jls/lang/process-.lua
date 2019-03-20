
return {
  kill = function(pid)
    if type(pid) == 'number' and pid > 0 then
      os.execute('taskkill /PID '..tostring(pid))
    end
  end,
  execute = function(pathOrArgs, env, dir)
    local line = 'start ""'
    if dir then
      line = line..' /D '..dir
    end
    local path
    if type(pathOrArgs) == 'string' then
      line = line..' '..pathOrArgs
      path = pathOrArgs
    elseif type(pathOrArgs) == 'table' then
      for _, a in ipairs(pathOrArgs) do
        line = line..' '..a
      end
      path = pathOrArgs[1]
    else
      return nil
    end
    os.execute(line)
    local imageName = string.gsub(path, '^[^/\\]*[/\\]', '', 1)
    --os.execute('tasklist /FI "IMAGENAME eq '..imageName..'" /FO csv /NH')
    return -1
  end
}
