--- This class represents an HTTP response.
-- @module jls.net.http.HttpResponseFile
-- @pragma nostrip

local FileDescriptor = require('jls.io.FileDescriptor')

--- The HttpResponseFile class represents an HTTP response.
-- The HttpResponseFile class inherits from @{HttpResponse}.
-- @type HttpResponseFile
return require('jls.lang.class').create(require('jls.net.http.HttpResponse'), function(httpResponseFile, super)

  --- Creates a new Response.
  -- @function HttpResponseFile:new
  function httpResponseFile:initialize(file, always)
    super.initialize(self)
    self.file = file
    self.always = always == true
  end

  function httpResponseFile:closeFileDescriptor()
    if self.fd then
      self.fd:closeSync()
      self.fd = false
    end
  end

  function httpResponseFile:readBody(value)
    if self.fd == nil then
      if (self:getStatusCode() == 200) or self.always then
        self.fd = FileDescriptor.openSync(self.file, 'w')
      else
        self.fd = false
      end
    end
    if self.fd then
      if value then
        self.fd:writeSync(value)
      else
        self:closeFileDescriptor()
      end
    else
      super.readBody(self, value)
    end
  end

  function httpResponseFile:setBody(value)
    if self.fd == nil and ((self:getStatusCode() == 200) or self.always) then
      self:readBody(value)
      self:closeFileDescriptor()
    else
      super.setBody(self, value)
    end
  end

  function httpResponseFile:close()
    self:closeFileDescriptor()
    super.close(self)
  end

end)
