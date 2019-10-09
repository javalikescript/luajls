--- A class that holds attributes.
-- @module jls.net.http.Attributes
-- @pragma nostrip

--- A class that holds attributes.
-- @type Attributes
return require('jls.lang.class').create(function(attributes)

  --- Creates a new Attributes.
  -- @function Attributes:new
  function attributes:initialize(attributes)
    self.attributes = {}
    if attributes and type(attributes) == 'table' then
      self:setAttributes(attributes)
    end
  end

  --- Sets the specified value for the specified name.
  -- @tparam string name the attribute name
  -- @param value the attribute value
  function attributes:setAttribute(name, value)
    self.attributes[name] = value
    return self
  end

  --- Returns the value for the specified name.
  -- @tparam string name the attribute name
  -- @return the attribute value
  function attributes:getAttribute(name)
    return self.attributes[name]
  end

  function attributes:getAttributes()
    return self.attributes
  end

  function attributes:setAttributes(attributes)
    for name, value in pairs(attributes) do
      self:setAttribute(name, value)
    end
    return self
  end
end)

