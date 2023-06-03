-- shift an argument table to be compatible with standalone lua or luvit
-- Before running any code, lua collects all command-line arguments in a global table called arg.
-- The script name goes to index 0, the first argument after the script name goes to index 1, and so on.
return function(args, init)
  if type(args) ~= 'table' then
    return {}
  end
  local scriptIndex = init or 2
  while true do
    local v = args[scriptIndex]
    if not v then
      break
    elseif v == '-' or v == '--' then -- stop handling options
      scriptIndex = scriptIndex + 1
      break
    elseif v == '-e' or v == '-l' then -- options with value
      scriptIndex = scriptIndex + 2
    elseif string.find(v, '^%-%w$') or string.find(v, '^%-%-[%w%-]+$') then -- options without value
      scriptIndex = scriptIndex + 1
    else
      break
    end
  end
  local sarg = {};
  for i = #args, -99, -1 do
    local v = args[i]
    if not v then
      break
    end
    sarg[i - scriptIndex] = v;
  end
  return sarg
end
