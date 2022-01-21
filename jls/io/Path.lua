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
  -- @tparam string pathname The name of the path.
  -- @return a new Path
  -- @usage
  --local workingDirectory = Path:new('work')
  --local configurationPath = Path:new(workingDirectory, 'configuration.json')
  function path:initialize(parent, pathname)
    if type(pathname) == 'string' then
      if Path:isInstance(parent) then
        parent = parent:getPathName()
      elseif type(parent) == 'string' then
        parent = Path.cleanPath(parent)
      else
        error('Invalid new Path arguments')
      end
      if pathname ~= '' then
        pathname = parent..Path.separator..Path.cleanPath(pathname)
      else
        pathname = parent
      end
    elseif type(parent) == 'string' then
      pathname = Path.cleanPath(parent)
    else
      error('Invalid new Path arguments')
    end
    self.path = pathname
    self.npath = Path.normalizePath(pathname, Path.separator)
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
  -- This is the creation value.
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

  --- Returns the parent path as a string.
  -- @treturn string the parent path.
  -- @usage
  --local configurationPath = Path:new('work/configuration.json')
  --configurationPath:getParent() -- returns 'work'
  function path:getParent()
    local npath = Path.normalizePath(self.path)
    local prefix, rel = Path.getPathPrefix(npath)
    if rel == '' then
      return nil
    end
    local parent = string.match(rel, '^(.+)[/\\][^/\\]+$')
    if parent then
      return prefix..parent
    end
    if prefix == '' then
      return nil
    end
    return prefix
  end

  --- Returns the parent of this path as a Path.
  -- @treturn Path the parent of this path as a Path.
  -- @usage
  --local configurationPath = File:new('work/configuration.json')
  --configurationPath:getParentPath():getName() -- returns 'work'
  function path:getParentPath()
    local pathname = self:getParent()
    if pathname then
      return Path:new(pathname)
    end
    return nil
  end

  --- Indicates whether or not this path is absolute.
  -- @treturn boolean true when this path is absolute, false otherwise.
  function path:isAbsolute()
    return Path.getPathPrefix(self.npath) ~= ''
  end

end, function(Path)

  --- The Operating System (OS) specific separator, '/' on Unix and '\\' on Windows.
  -- @field Path.separator
  Path.separator = string.sub(package.config, 1, 1) or '/'

  -- Returns the path prefix and the path relative.
  -- The prefix is empty when the path is relative.
  function Path.getPathPrefix(pathname)
    local prefix, rel = string.match(pathname, '^([/\\])[/\\]*(.*)$')
    if prefix then
      return prefix, rel
    end
    prefix, rel = string.match(pathname, '^(%a:)[/\\]*([^/\\]?.*)$')
    if prefix then
      return prefix..'\\', rel
    end
    return '', pathname
  end

  -- Returns the specified path without extra slashes.
  function Path.cleanPath(pathname)
    if type(pathname) == 'string' then
      -- clean extra slashes
      pathname = string.gsub(pathname, '([/\\])[/\\]+', '%1')
      if string.len(pathname) > 1 and not string.find(pathname, '^%a:[/\\]$') then
        pathname = string.gsub(pathname, '[/\\]$', '')
      end
    end
    return pathname
  end

  -- Returns the specified path without dots.
  function Path.normalizePath(pathname, separator)
    if type(pathname) == 'string' then
      local sep = separator or string.match(pathname, '[/\\]') or Path.separator
      -- clean dots
      local prefix, rel = Path.getPathPrefix(pathname)
      rel = '/'..rel..'/'
      if string.find(rel, '[/\\]%.%.?[/\\]') then
        local ss = {}
        for s in string.gmatch(rel, '[^/\\]+') do
          if s == '..' and #ss > 0 then
            table.remove(ss)
          elseif s ~= '.' and s ~= '' then
            table.insert(ss, s)
          end
        end
        rel = table.concat(ss, sep)
        if rel == '' and prefix == '' then
          return '.'
        end
        return prefix..rel
      else
        return string.gsub(pathname, '[/\\]+', sep)
      end
    end
    return pathname
  end

  function Path.extractExtension(pathname)
    return string.match(pathname, '%.([^/\\%.]*)$') -- or ''
  end

  function Path.extractBaseName(pathname)
    return string.match(pathname, '^(.+)%.[^%.]*$') or pathname
  end

  -- TODO remove, deprecated
  function Path.asPathName(pathOrName)
    if type(pathOrName) == 'table' and type(pathOrName.getPathName) == 'function' then
      return pathOrName:getPathName()
    end
    return Path.cleanPath(pathOrName)
  end

  function Path.asNormalizedPath(path)
    if type(path) == 'table' and type(path.npath) == 'string' then
      return path.npath
    end
    return Path.normalizePath(Path.cleanPath(path), Path.separator)
  end

end)
