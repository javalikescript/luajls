local status, lcLib = pcall(require, 'luachild')
if status and lcLib then
  return lcLib.setenv
end
return require('jls.lang.class').notImplementedFunction
