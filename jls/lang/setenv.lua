local status, lcLib = pcall(require, 'luachild')
if status and lcLib then
  return lcLib.setenv
end
return function(name, value)
  error('not available')
end
