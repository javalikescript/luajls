local isWindowsOS = string.sub(package.config, 1, 1) == '\\'

return function(args)
  local pargs = {}
  for _, arg in ipairs(args) do
    local earg = arg
    if isWindowsOS then
      -- see https://ss64.com/nt/syntax-esc.html
      if string.find(arg, '[%s"&\\<>%^|%%]') and not string.match(arg, '^[<>|&]+$') then
        earg = '"'..string.gsub(arg, '"', '""')..'"'
      end
    else
      -- see https://www.oreilly.com/library/view/learning-the-bash/1565923472/ch01s09.html
      if string.find(arg, '[%s"~`#$&%*%(%)\\|%[%]{};\'"<>/%?!]') and not string.match(arg, '^[<>|&]+$') then
        earg = '"'..string.gsub(arg, '["\\]', '\\%&1')..'"'
      end
    end
    table.insert(pargs, earg)
  end
  if isWindowsOS then
    return '"'..table.concat(pargs, ' ')..'"'
  end
  return table.concat(pargs, ' ')
end