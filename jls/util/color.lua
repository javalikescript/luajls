-- Provide color functions.
-- @module jls.util.color

local color = {}

-- Transforms a color expressed with hue, saturation and value to red, green and blue.
-- @tparam number h the hue value from 0 to 1.
-- @tparam number s the saturation value from 0 to 1.
-- @tparam number v the value from 0 to 1.
-- @treturn number the red component value from 0 to 1.
-- @treturn number the green component value from 0 to 1.
-- @treturn number the blue component value from 0 to 1.
function color.hsvToRgb(h, s, v)
  if s <= 0 then
    return v, v, v
  end
  local c = v * s -- chroma
  local hp = h * 6
  local x = c * (1 - math.abs((hp % 2) - 1))
  local r, g, b
  if hp <= 1 then
    r, g, b = c, x, 0
  elseif hp <= 2 then
    r, g, b = x, c, 0
  elseif hp <= 3 then
    r, g, b = 0, c, x
  elseif hp <= 4 then
    r, g, b = 0, x, c
  elseif hp <= 5 then
    r, g, b = x, 0, c
  else
    r, g, b = c, 0, x
  end
  local m = v - c
  return r + m, g + m, b + m
end

-- Transforms a color expressed with red, green and blue to hue, saturation and value.
-- @tparam number r the red component value from 0 to 1.
-- @tparam number g the green component value from 0 to 1.
-- @tparam number b the blue component value from 0 to 1.
-- @treturn number the hue value from 0 to 1.
-- @treturn number the saturation value from 0 to 1.
-- @treturn number the value from 0 to 1.
function color.rgbToHsv(r, g, b)
  local minValue = math.min(r, g, b)
  local maxValue = math.max(r, g, b)
  local deltaValue = maxValue - minValue
  local h, s
  local v = maxValue
  if maxValue == 0 then
    h = 0 -- undefined
    s = 0
  else
    s = deltaValue / maxValue
    if deltaValue == 0 then
      h = 0
    elseif r == maxValue then
      h = (g - b) / deltaValue
      if h < 0 then
        h = h + 6
      end
    elseif g == maxValue then
      h = 2 + (b - r) / deltaValue
    else
      h = 4 + (r - g) / deltaValue
    end
    h = h / 6
  end
  return h, s, v
end

return color