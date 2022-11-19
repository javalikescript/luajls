--- Represents an abnormal event.
-- An exception instance captures the error message and the associated stack.
-- @module jls.lang.Exception
-- @pragma nostrip

local class = require('jls.lang.class')

--- The Exception class.
-- @type Exception
return class.create(function(exception, _, Exception)

  --- Creates a new Exception.
  -- The stack trace and the name will be generated automatically.
  -- @param[opt] message the exception message.
  -- @param[opt] cause the exception cause.
  -- @tparam[opt] string stack the exception stack.
  -- @tparam[opt] string name the exception name.
  -- @function StringBuffer:new
  function exception:initialize(message, cause, stack, name)
    self.name = name or class.getName(self:getClass()) or 'Exception'
    self.message = message
    self.cause = cause
    self.stack = stack or debug.traceback(nil, 3)
  end

  function exception:getName()
    return self.name
  end

  --- Returns the message of this exception.
  -- @return the message of this exception possibly nil.
  function exception:getMessage()
    return self.message
  end

  --- Returns the cause of this exception.
  -- @return the cause of this exception if any or nil.
  function exception:getCause()
    return self.cause
  end

  --- Returns the stack of this exception.
  -- @treturn string the stack of this exception.
  function exception:getStackTrace()
    return self.stack
  end

  -- Throws this exception.
  function exception:throw()
    error(self, 0)
  end

  -- Returns the string representation of this exception.
  -- It includes the name, message, stack and cause.
  -- @treturn string the string representation of this exception.
  function exception:toString()
    local s = self.name..': '..tostring(self.message)..'\n'..self.stack
    if self.cause ~= nil then
      s = s..'\nCaused by: '..tostring(self.cause)
    end
    --s = string.gsub(self.stack, '\n', '\r\n')
    return s
  end

  function Exception.throw(...)
    Exception:new(...):throw()
  end

  function Exception.getMessage(e)
    if Exception:isInstance(e) then
      return e:getMessage()
    end
    return e
  end

  local function handleError(err)
    if Exception:isInstance(err) then
      return err
    end
    return Exception:new(err, nil, debug.traceback(nil, 2))
  end

  --- Calls the specified function with the given arguments in protected mode.
  -- @tparam function fn the function to call in protected mode.
  -- @param[opt] ... the arguments to call the function with.
  -- @treturn boolean true if the call succeeds without errors.
  -- @return the returned values of the call or the Exception in case of error.
  function Exception.pcall(fn, ...)
    return xpcall(fn, handleError, ...)
  end

  function Exception.try(fn, ...)
    local results = table.pack(Exception.pcall(fn, ...))
    local function apply(t, f)
      if type(f) == 'function' then
        return Exception.try(f, table.unpack(results, 2, results.n))
      end
      return t
    end
    if results[1] then
      return {
        catch = function(t) return t end,
        next = apply
      }
    end
    return {
      catch = apply,
      next = function(t, _, f) return apply(t, f) end
    }
  end

end)