--- This class enables to deal with composite data type.
-- @module jls.util.Struct

local logger = require('jls.lang.logger')
local integers = require('jls.util.integers')

--- The Struct class.
-- The Struct provides a way to C like structure.
-- @type Struct
return require('jls.lang.class').create(function(struct)

  local TYPE_ID = {
    Char = 100,
    SignedByte = 101,
    UnsignedByte = 102,
    SignedShort = 201,
    UnsignedShort = 202,
    SignedInt = 401,
    UnsignedInt = 402,
    SignedLong = 801,
    UnsignedLong = 802
  }

  local TYPE_SIZE = {
    Char = 1,
    SignedByte = 1,
    UnsignedByte = 1,
    SignedShort = 2,
    UnsignedShort = 2,
    SignedInt = 4,
    UnsignedInt = 4,
    SignedLong = 8,
    UnsignedLong = 8
  }

  --- Creates a new Struct.
  -- @function Struct:new
  -- @tparam table structDef the structure definition as field-type key-value pairs
  -- @tparam string byteOrder bigEndian or littleEndian
  -- @return a new Struct
  function struct:initialize(structDef, byteOrder)
    self.struct = {}
    self.int = integers.be
    local position = 0
    for i, def in ipairs(structDef) do
      local id = TYPE_ID[def.type]
      if not id then
        error('Invalid Struct definition type "'..tostring(def.type)..'" at index '..tostring(i))
      end
      local length = def.length or 1
      local size = TYPE_SIZE[def.type] * length
      table.insert(self.struct, {
        id = id,
        length = length,
        name = def.name,
        position = position,
        size = size,
        type = def.type
      })
      position = position + size
    end
    self.size = position;
    self:setOrder(byteOrder)
  end

  --- Sets the byte order.
  -- @tparam string byteOrder bigEndian or littleEndian
  function struct:setOrder(byteOrder)
    local byteOrderType = type(byteOrder)
    if byteOrderType == 'string' then
      local bo = string.lower(string.sub(byteOrder, 1, 1))
      if bo == 'b' then
        self.int = integers.be
      elseif bo == 'l' then
        self.int = integers.le
      end
    elseif byteOrderType == 'table' then
      self.int = byteOrder
    end
    return self
  end

  --- Returns the size of this Struct that is the total size of its fields.
  -- @treturn number the size of this Struct.
  function struct:getSize()
    return self.size
  end

  --- Decodes the specifed byte array as a string.
  -- @tparam string s the value to decode as a string
  -- @treturn table the decoded values.
  function struct:fromString(s)
    local t = {}
    -- TODO Check size
    for i, def in ipairs(self.struct) do
      local rawValue = string.sub(s, def.position + 1, def.position + def.size)
      local value
      if def.id == TYPE_ID.Char then
        value = rawValue
      elseif def.id == TYPE_ID.SignedByte then
        value = self.int.toInt8(rawValue)
      elseif def.id == TYPE_ID.UnsignedByte then
        value = self.int.toUInt8(rawValue)
      elseif def.id == TYPE_ID.SignedShort then
        value = self.int.toInt16(rawValue)
      elseif def.id == TYPE_ID.UnsignedShort then
        value = self.int.toUInt16(rawValue)
      elseif def.id == TYPE_ID.SignedInt then
        value = self.int.toInt32(rawValue)
      elseif def.id == TYPE_ID.UnsignedInt then
        value = self.int.toUInt32(rawValue)
      end
      t[def.name] = value
    end
    return t
  end

  --- Encodes the specifed values provided as a table.
  -- @tparam string t the values to encode as a table
  -- @treturn string the encoded values as a string.
  function struct:toString(t)
    local ts = {}
    for i, def in ipairs(self.struct) do
      local value = t[def.name]
      if not value then
        error('Missing value for field "'..tostring(def.name)..'" at index '..tostring(i))
      end
      local rawValue
      if def.id == TYPE_ID.Char then
        if #value == def.size then
          rawValue = value
        elseif #value < def.size then
          rawValue = value..string.rep(' ', def.size - #value)
        else
          rawValue = string.sub(value, 1, def.size)
        end
      elseif def.id == TYPE_ID.SignedByte then
        rawValue = self.int.fromInt8(value)
      elseif def.id == TYPE_ID.UnsignedByte then
        rawValue = self.int.fromUInt8(value)
      elseif def.id == TYPE_ID.SignedShort then
        rawValue = self.int.fromInt16(value)
      elseif def.id == TYPE_ID.UnsignedShort then
        rawValue = self.int.fromUInt16(value)
      elseif def.id == TYPE_ID.SignedInt then
        rawValue = self.int.fromInt32(value)
      elseif def.id == TYPE_ID.UnsignedInt then
        rawValue = self.int.fromUInt32(value)
      end
      if not rawValue then
        error('Cannot encode value "'..tostring(value)..'" for field "'..tostring(def.name)..'" at index '..tostring(i))
      end
      table.insert(ts, rawValue)
    end
    return table.concat(ts)
  end

end)