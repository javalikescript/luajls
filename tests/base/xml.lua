local lu = require('luaunit')

local xml = require("jls.util.xml")

local function normalize(s)
  local ns = s
  ns = string.gsub(ns, '^%s*', '')
  ns = string.gsub(ns, '%s*\r?\n%s*', '')
  return ns
end

local function checkEncodeDecode(s)
  local ds = xml.decode(s)
  local es = xml.encode(ds)
  lu.assertEquals(normalize(es), normalize(s))
end

function Test_decode_encode()
  checkEncodeDecode([[<people>
  <person type="natural">
    <name>Manoel</name>
    <city>Palmas-TO</city>
  </person>
  <person type="legal">
    <name>University of Brasília</name>
    <city>Brasília-DF</city>
  </person>
</people>]])
end

--<?xml version="1.0" encoding="utf-8" ?>

function Test_decode_encode_ns()
  checkEncodeDecode([[<n:a xmlns:n="my:"><n:b>text</n:b></n:a>]])
end

function Test_decode_encode_escaped()
  checkEncodeDecode([[<a><b c=" &apos;1 &amp; 1&#x0a;line" /><d>"2' &amp; 2</d></a>]])
end

function getSampleXmlTable()
  return {
    name = 'people',
    {
      name = 'person',
      attr = {type = 'fiction'},
      {name = 'name', 'Luigi'}
    }
  }
end

function getSampleXmlTable2()
  return {
    name = 'people',
    {
      name = 'person',
      attr = {type = 'fiction'},
      {name = 'name', 'Luigi'}
    },
    {
      name = 'person',
      attr = {type = 'real'},
      {name = 'name', 'Mario'}
    }
  }
end

function Test_encode_decode()
  local t = getSampleXmlTable()
  lu.assertEquals(xml.decode(xml.encode(t)), t)
end

function Test_encode()
  lu.assertEquals(xml.encode(getSampleXmlTable()),
    '<people><person type="fiction"><name>Luigi</name></person></people>')
end

function Test_encode_2()
  lu.assertEquals(xml.encode(getSampleXmlTable2()),
    '<people><person type="fiction"><name>Luigi</name></person><person type="real"><name>Mario</name></person></people>')
end

function Test_encode_ns()
  lu.assertEquals(xml.encode(xml.setNamespace(getSampleXmlTable(), 'DNS:', 'D')),
    '<D:people xmlns:D="DNS:"><D:person type="fiction"><D:name>Luigi</D:name></D:person></D:people>')
end

os.exit(lu.LuaUnit.run())
