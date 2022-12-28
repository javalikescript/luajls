--- Provide Struct class.
-- @module jls.util.Struct

--- The Struct class.
-- The Struct provides a way to represents C like structure.
-- @type Struct
return require('jls.lang.class').create(function(struct)

  --- Creates a new Struct.
  -- @function Struct:new
  -- @tparam table structDef the fields structure definition with name and type, convertion option
  -- @tparam[opt] string byteOrder '<', '>' or '=' for little, big or native endian
  -- @return a new Struct
  function struct:initialize(structDef, byteOrder)
    self.struct = structDef or {}
    local format = byteOrder or '='
    local fixedSize = true
    for _, def in ipairs(self.struct) do
      local ct = string.gsub(def.type, '^S(%d+)$', 'c%1')
      if string.find(ct, '^[sz]') then
        fixedSize = false
      end
      format = format..ct
    end
    self.format = format
    self.size = fixedSize and string.packsize(self.format) or -1
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
    local values = table.pack(string.unpack(self.format, s))
    for i, def in ipairs(self.struct) do
      local value = values[i]
      if string.find(def.type, '^S') then
        value = string.gsub(value, '\0*$', '')
      end
      t[def.name] = value
    end
    return t
  end

  --- Encodes the specifed values provided as a table.
  -- @tparam string t the values to encode as a table
  -- @tparam[opt] boolean strict true to indicate that all the value are expected
  -- @treturn string the encoded values as a string.
  function struct:toString(t, strict)
    if type(t) ~= 'table' then
      return ''
    end
    local values = {}
    for i, def in ipairs(self.struct) do
      local value = t[def.name]
      if value == nil then
        if strict then
          error('Missing value for field "'..tostring(def.name)..'" at index '..tostring(i))
        end
        if string.find(def.type, '^[csSz]') then
          value = ''
        else
          value = 0
        end
      end
      table.insert(values, value)
    end
    return string.pack(self.format, table.unpack(values))
  end

end, function(Struct)

  --- Returns the string representing the specified integer
  -- The most significant bit is set to 1 to indicate that another byte is used.
  -- @tparam number i the integer to encode
  -- @treturn string the encoded value as a string.
  function Struct.encodeVariableByteInteger(i)
    if i < 0 then
      return nil
    elseif i < 128 then
      return string.char(i)
    elseif i < 16384  then
      return string.char(0x80 | (i & 0x7f), (i >> 7) & 0x7f)
    elseif i < 2097152  then
      return string.char(0x80 | (i & 0x7f), 0x80 | ((i >> 7) & 0x7f), (i >> 14) & 0x7f)
    elseif i <= 268435455  then
      return string.char(0x80 | (i & 0x7f), 0x80 | ((i >> 7) & 0x7f), 0x80 | ((i >> 14) & 0x7f), (i >> 21) & 0x7f)
    end
    return nil
  end

  --- Returns the integer represented by the specified string
  -- @tparam string s the encoded integer
  -- @tparam[opt] number offset the starting offset, default is 1
  -- @treturn number the decoded integer or nil.
  -- @treturn number the end offset
  function Struct.decodeVariableByteInteger(s, offset)
    offset = offset or 1
    local i = 0
    for l = 0, 3 do
      local b = string.byte(s, offset + l)
      i = ((b & 0x7f) << (7 * l)) | i
      if (b & 0x80) ~= 0x80 then
        return i, offset + l + 1
      end
    end
    return nil
  end

end)
