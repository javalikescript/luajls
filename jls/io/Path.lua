--[[--
Provide a representation of a file system path name.

@module jls.io.Path
@pragma nostrip

@usage
local configurationPath = File:new('work/configuration.json')
configurationPath:getName() -- returns 'configuration.json'
configurationPath:getParentPath():getName() -- returns 'work'

]]

--local logger = require('jls.lang.logger')

--- A Path class.
-- A Path instance represents a file or a directory.
-- @type Path
return require('jls.lang.class').create(function(path, _, Path)
  --- Creates a new Path representing the specified pathname.
  -- @function Path:new
  -- @param[opt] parent The optional parent as a string or a @{Path}.
  -- @tparam string path The name of the path.
  -- @return a new Path
  -- @usage
  --local workingDirectory = Path:new('work')
  --local configurationPath = Path:new(workingDirectory, 'configuration.json')
  function path:initialize(parent, path)
    if type(path) == 'string' then
      if Path:isInstance(parent) then
        parent = parent:getPathName()
      elseif type(parent) == 'string' then
        parent = Path.cleanPath(parent)
      else
        error('Invalid new Path arguments')
      end
      if path ~= '' then
        path = parent..Path.separator..Path.cleanPath(path)
      else
        path = parent
      end
    elseif type(parent) == 'string' then
      path = Path.cleanPath(parent)
    else
      error('Invalid new Path arguments')
    end
    self.path = path
    self.npath = Path.normalizePath(path)
  end

  --- Returns the name of the file or directory of this Path.
  -- The name is the last last part of the path.
  -- @treturn string the name of the file or directory.
  -- @usage
  --local configurationPath = Path:new('work/configuration.json')
  --configurationPath:getName() -- returns 'configuration.json'
  function path:getName()
    return string.gsub(self.npath, '^.*[/\\]', '', 1)
  end

  function path:getExtension()
    return Path.extractExtension(self.npath)
  end

  function path:getBaseName()
    return Path.extractBaseName(self:getName())
  end

  --- Returns the string representation of this Path.
  -- @treturn string the string representation of this Path.
  -- @usage
  --local configurationPath = Path:new('work/configuration.json')
  --configurationPath:getPathName() -- returns 'work/configuration.json'
  function path:getPathName()
    return self.path
  end

  --- Returns the string representation of this Path.
  -- @treturn string the string representation of this Path.
  -- @usage
  --local configurationPath = Path:new('work/configuration.json')
  --configurationPath:toString() -- returns 'work/configuration.json'
  function path:toString()
    return self.path
  end

  function path:getPathPrefix()
    local prefix, path = string.match(self.path, '^([/\\]+)(.*)$')
    if prefix then
      return prefix, path
    end
    prefix, path = string.match(self.path, '^(%a:[/\\]*)([^/\\]?.*)$')
    if prefix then
      return prefix, path
    end
    return '', self.path
  end

  --- Returns the parent path as a string.
  -- @treturn string the parent path.
  -- @usage
  --local configurationPath = Path:new('work/configuration.json')
  --configurationPath:getParent() -- returns 'work'
  function path:getParent()
    if self:isAbsolute() then
      local prefix, path = self:getPathPrefix()
      if path == '' then
        return nil
      end
      local parentPath = string.match(path, '^(.+)[/\\][^/\\]+$')
      if parentPath then
        return prefix..parentPath
      end
      return prefix
    end
    return string.match(self.path, '^(.+)[/\\][^/\\]+$')
  end

  --- Returns the parent of this path as a Path.
  -- @treturn Path the parent of this path as a Path.
  -- @usage
  --local configurationPath = File:new('work/configuration.json')
  --configurationPath:getParentPath():getName() -- returns 'work'
  function path:getParentPath()
    local p = self:getParent()
    if p then
      return Path:new(p)
    end
    return nil
  end

  --- Indicates whether or not this path is absolute.
  -- @treturn boolean true when this path is absolute, false otherwise.
  function path:isAbsolute()
    if string.find(self.npath, '^[/\\]') or string.find(self.npath, '^%a:[/\\]') then
      return true
    end
    return false
  end

end, function(Path)

  --- The Operating System (OS) specific separator, '/' on Unix and '\\' on Windows.
  -- @field Path.separator
  Path.separator = string.sub(package.config, 1, 1) or '/'

  function Path.cleanPath(path)
    if type(path) == 'string' then
      path = string.gsub(path, '[/\\]+', Path.separator)
      if string.len(path) > 1 and not string.find(path, '^%a:[/\\]$') then
        path = string.gsub(path, '[/\\]$', '')
      end
    end
    return path
  end

  function Path.normalizePath(path)
    if type(path) == 'string' then
      -- clean extra slashes
      -- TODO find a better way to clean extra slashes, if possible in a single pass
      path = string.gsub(path, '[/\\]%.([/\\])', '%1')
      path = string.gsub(path, '[^/\\]+[/\\]%.%.[/\\]', '')
      path = string.gsub(path, '[/\\][^/\\]+[/\\]%.%.$', '')
      path = string.gsub(path, '[/\\]%.$', '')
      path = string.gsub(path, '^%.[/\\]', '')
    end
    return path
  end

  function Path.extractExtension(path)
    return string.match(path, '%.([^/\\%.]*)$') -- or ''
  end

  function Path.extractBaseName(path)
    return string.match(path, '^(.+)%.[^%.]*$') or path
  end

  function Path.asPathName(path)
    if type(path) == 'table' and type(path.getPathName) == 'function' then
      return path:getPathName()
    end
    return Path.cleanPath(path)
  end

end)
