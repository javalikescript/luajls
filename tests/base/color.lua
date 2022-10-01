local lu = require('luaunit')

local color = require('jls.util.color')

local function formatHsv(h, s, v)
  return tostring(math.floor(h * 360))..','..tostring(s)..','..tostring(v)
end

local function formatRgb(r, g, b)
  return tostring(math.floor(r * 255))..','..tostring(math.floor(g * 255))..','..tostring(math.floor(b * 255))
end

local ERROR_MARGIN = 1 / 1000

local function assertTripletEquals(actualA, actualB, actualC, expectedA, expectedB, expectedC, message)
  lu.assertAlmostEquals(actualA, expectedA, ERROR_MARGIN, message)
  lu.assertAlmostEquals(actualB, expectedB, ERROR_MARGIN, message)
  lu.assertAlmostEquals(actualC, expectedC, ERROR_MARGIN, message)
end

function Test_hsvToRgb()
  local function assertHsvToRgb(h, s, v, r, g, b)
    local ar, ag, ab = color.hsvToRgb(h, s, v)
    assertTripletEquals(ar, ag, ab, r, g, b, formatHsv(h, s, v)..' => '..formatRgb(r, g, b))
  end
  assertHsvToRgb(0, 0, 0, 0, 0, 0)
  assertHsvToRgb(0, 1, 1, 1, 0, 0)
  assertHsvToRgb(120 / 360, 1, 0.5, 0, 0.5, 0)
  assertHsvToRgb(0.5, 0.5, 1, 0.5, 1, 1)
end

function Test_rgbToHsv()
  local function assertRgbToHsv(r, g, b, h, s, v)
    local ah, as, sv = color.rgbToHsv(r, g, b)
    assertTripletEquals(ah, as, sv, h, s, v, formatRgb(r, g, b)..' => '..formatHsv(h, s, v))
  end
  assertRgbToHsv(0, 0, 0, 0, 0, 0)
  assertRgbToHsv(1, 0, 0, 0, 1, 1)
  assertRgbToHsv(0, 0.5, 0, 120 / 360, 1, 0.5)
  assertRgbToHsv(0.5, 1, 1, 0.5, 0.5, 1)
end

function Test_hsvToRgb_then_rgbToHsv()
  local function assertHsvToRgbThenRgbToHsv(h, s, v)
    local ah, as, sv = color.rgbToHsv(color.hsvToRgb(h, s, v))
    assertTripletEquals(ah, as, sv, h, s, v, formatHsv(h, s, v))
  end
  assertHsvToRgbThenRgbToHsv(0, 0, 0)
  assertHsvToRgbThenRgbToHsv(0.9, 1, 1)
  --assertHsvToRgbThenRgbToHsv(1, 1, 1)
  assertHsvToRgbThenRgbToHsv(0.2, 0.5, 0.8)
  for h = 0.1, 1, 0.2 do
    for s = 0.1, 1, 0.2 do
      for v = 0.1, 1, 0.2 do
        assertHsvToRgbThenRgbToHsv(h, s, v)
      end
    end
  end
end

function Test_rgbToHsv_then_hsvToRgb()
  local function assertRgbToHsvThenHsvToRgb(r, g, b)
    local ar, ag, ab = color.hsvToRgb(color.rgbToHsv(r, g, b))
    assertTripletEquals(ar, ag, ab, r, g, b, formatRgb(r, g, b))
  end
  assertRgbToHsvThenHsvToRgb(0, 0, 0)
  assertRgbToHsvThenHsvToRgb(1, 1, 1)
  assertRgbToHsvThenHsvToRgb(0.2, 0.5, 0.8)
  for r = 0, 1, 0.1 do
    for g = 0, 1, 0.1 do
      for b = 0, 1, 0.1 do
        assertRgbToHsvThenHsvToRgb(r, g, b)
      end
    end
  end
end

os.exit(lu.LuaUnit.run())
