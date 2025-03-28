local lu = require('luaunit')

local class = require('jls.lang.class')

function Test_initialize()
  local initialized = false
  local selfInitialized = nil
  local Account = class.create()
  function Account.prototype:initialize(a, b)
    initialized = true
    selfInitialized = self
    self.a = a
    self.b = b
  end
  local anAccount = Account:new('Hello', 123)
  lu.assertEquals(initialized, true)
  lu.assertEquals(selfInitialized, anAccount)
  lu.assertEquals(anAccount.a, 'Hello')
  lu.assertEquals(anAccount.b, 123)
end

function Test_getClass()
  local Account = class.create()
  local anAccount = Account:new()
  lu.assertEquals(anAccount:getClass(), Account)
  lu.assertEquals(anAccount.getClass(), nil)
  lu.assertEquals(class.getClass(anAccount), Account)
  lu.assertEquals(class.getClass({}), nil)
end

function Test_getSuperclass()
  local Account = class.create()
  local LimitedAccount = class.create(Account)
  local anAccount = Account:new()
  local aLimitedAccount = LimitedAccount:new()
  lu.assertEquals(anAccount:getClass(), Account)
  lu.assertIsNil(Account.super)
  lu.assertIsNil(anAccount:getClass().super)
  lu.assertEquals(aLimitedAccount:getClass(), LimitedAccount)
  lu.assertEquals(LimitedAccount.super, Account)
  lu.assertEquals(aLimitedAccount:getClass().super, Account)
end

function Test_super()
  local Account = class.create()
  function Account.prototype:initialize(a)
    self.a = a
  end
  local LimitedAccount = class.create(Account)
  function LimitedAccount.prototype:initialize(a, b)
    LimitedAccount.super.prototype.initialize(self, a)
    self.b = b
  end
  local anAccount = Account:new('Hello', 123)
  local aLimitedAccount = LimitedAccount:new('Hello', 123)
  lu.assertEquals(anAccount.a, 'Hello')
  lu.assertEquals(anAccount.b, nil)
  lu.assertEquals(aLimitedAccount.a, 'Hello')
  lu.assertEquals(aLimitedAccount.b, 123)
end

function Test_isInstance()
  local Car = class.create()
  local Account = class.create()
  local LimitedAccount = class.create(Account)
  local aCar = Car:new()
  local anAccount = Account:new()
  local aLimitedAccount = LimitedAccount:new()

  lu.assertEquals(Account:isInstance(anAccount), true)
  lu.assertEquals(Account:isInstance(aLimitedAccount), true)
  lu.assertEquals(LimitedAccount:isInstance(anAccount), false)
  lu.assertEquals(LimitedAccount:isInstance(aLimitedAccount), true)
  lu.assertEquals(Account:isInstance(aCar), false)
  lu.assertEquals(Car:isInstance(aCar), true)
  lu.assertEquals(Car:isInstance(anAccount), false)
  lu.assertEquals(Car:isInstance(aLimitedAccount), false)

  lu.assertEquals(class.isInstance(LimitedAccount, aLimitedAccount), true)
  lu.assertEquals(class.isInstance(Account, aLimitedAccount), true)
  lu.assertEquals(class.isInstance(Account, aCar), false)
end

function Test_asInstance()
  local Car = class.create()
  function Car.prototype:initialize(a, b)
    self.ab = tostring(a)..' '..tostring(b)
  end
  local aCar = Car:new(1, 2)
  local bCar = class.asInstance(Car, aCar)
  local cCar = class.asInstance(Car, 3, 4)
  lu.assertEquals(Car:isInstance(aCar), true)
  lu.assertEquals(Car:isInstance(bCar), true)
  lu.assertEquals(Car:isInstance(cCar), true)
  lu.assertEquals(bCar, aCar)
  lu.assertEquals(aCar.ab, '1 2')
  lu.assertEquals(cCar.ab, '3 4')
end

function Test_clone()
  local Car = class.create()
  function Car.prototype:initialize(color)
    self.color = color
  end
  function Car.prototype:getColor()
    return self.color
  end
  local aBlueCar = Car:new('blue')
  local aClonedCar = class.cloneInstance(aBlueCar)
  lu.assertEquals(Car:isInstance(aClonedCar), true)
  lu.assertEquals(aClonedCar:getColor(), 'blue')
end

function Test_clone_serder()
  local Car = class.create(function(car)
    function car:initialize(color)
      self.color = color
    end
    function car:getColor()
      return self.color
    end
      function car:serialize(write)
      write(self.color..'(serialized)')
    end
    function car:deserialize(read)
      self.color = read('string')
    end
  end)
  package.loaded['tests.Car'] = Car
  local aBlueCar = Car:new('blue')
  local aClonedCar = class.cloneInstance(aBlueCar)
  package.loaded['tests.Car'] = nil
  lu.assertEquals(Car:isInstance(aClonedCar), true)
  lu.assertEquals(aClonedCar:getColor(), 'blue(serialized)')
end

function Test_inheritance()
  local Account = class.create()
  function Account.prototype:initialize(amount)
    self.amount = amount
  end
  function Account.prototype:debit(debitAmount)
    self.amount = self.amount - debitAmount
  end
  local LimitedAccount = class.create(Account)
  function LimitedAccount.prototype:debit(debitAmount)
    if self.amount - debitAmount > 0 then
      LimitedAccount.super.prototype.debit(self, debitAmount)
    end
  end
  local anAccount = Account:new(123)
  local aLimitedAccount = LimitedAccount:new(123)
  lu.assertEquals(anAccount.amount, 123)
  lu.assertEquals(aLimitedAccount.amount, 123)
  anAccount:debit(100)
  aLimitedAccount:debit(100)
  lu.assertEquals(anAccount.amount, 23)
  lu.assertEquals(aLimitedAccount.amount, 23)
  anAccount:debit(100)
  aLimitedAccount:debit(100)
  lu.assertEquals(anAccount.amount, -77)
  lu.assertEquals(aLimitedAccount.amount, 23)
  -- remove override method
  LimitedAccount.prototype.debit = nil
  aLimitedAccount:debit(100)
  lu.assertEquals(aLimitedAccount.amount, -77)
  -- check if inherited method is still there
  --LimitedAccount.prototype.debit = nil
  aLimitedAccount:debit(100)
  lu.assertEquals(aLimitedAccount.amount, -177)
end

function Test_define()
  local Account = class.create(function(pt)
    function pt:initialize(amount)
      self.amount = amount
    end
    function pt:debit(debitAmount)
      self.amount = self.amount - debitAmount
    end
  end)
  function Account:getName()
    return 'Account'
  end
  local LimitedAccount = class.create(Account, function(pt, super)
    function pt:debit(debitAmount)
      if self.amount - debitAmount > 0 then
        super.debit(self, debitAmount)
      end
    end
  end)
  local anAccount = Account:new(123)
  local aLimitedAccount = LimitedAccount:new(123)
  lu.assertEquals(anAccount.amount, 123)
  lu.assertEquals(aLimitedAccount.amount, 123)
  anAccount:debit(100)
  aLimitedAccount:debit(100)
  lu.assertEquals(anAccount.amount, 23)
  lu.assertEquals(aLimitedAccount.amount, 23)
  anAccount:debit(100)
  aLimitedAccount:debit(100)
  lu.assertEquals(anAccount.amount, -77)
  lu.assertEquals(aLimitedAccount.amount, 23)
  lu.assertNil(LimitedAccount:getName())
end

local TEST_CLASS_NAME = 'tests.MyClass'
assert(package.loaded[TEST_CLASS_NAME] == nil)

function Test_getName()
  lu.assertEquals(class.getName(class), 'jls.lang.class')
  lu.assertNil(class.getName({}))
  local MyInnerClass = {}
  package.loaded[TEST_CLASS_NAME] = {MyInnerClass = MyInnerClass}
  lu.assertEquals(class.getName(MyInnerClass), TEST_CLASS_NAME..'$MyInnerClass')
  package.loaded[TEST_CLASS_NAME] = nil
end

function Test_byName()
  lu.assertEquals(class.byName('jls.lang.class'), class)
  lu.assertFalse(pcall(class.byName, TEST_CLASS_NAME))
  local MyInnerClass = {MySubInnerClass = {}}
  package.loaded[TEST_CLASS_NAME] = {MyInnerClass = MyInnerClass}
  local status, m = pcall(class.byName, TEST_CLASS_NAME..'$MyInnerClass')
  local status2, m2 = pcall(class.byName, TEST_CLASS_NAME..'$MyInnerClass.MySubInnerClass')
  package.loaded[TEST_CLASS_NAME] = nil
  lu.assertTrue(status)
  lu.assertEquals(m, MyInnerClass)
  lu.assertTrue(status2)
  lu.assertEquals(m2, MyInnerClass.MySubInnerClass)
end

local function createDecoratedClass()
  return class.create(function(pt)
    function pt:initialize(name)
      self.name = name or ''
    end
    function pt:toString()
      return self.name
    end
    function pt:length()
      return #self.name
    end
    function pt:equals(c)
      return self.name == c.name
    end
  end)
end

function Test_decorations()
  local Car = createDecoratedClass()
  local aCar = Car:new('ami')
  lu.assertEquals(tostring(aCar), 'ami')
  local anotherCar = Car:new('friend')
  lu.assertNotIs(aCar, anotherCar)
  anotherCar.name = 'ami'
  lu.assertIs(aCar, anotherCar)

  local bCar = Car('bmi')
  lu.assertTrue(Car:isInstance(bCar))
  lu.assertEquals(bCar:toString(), 'bmi')

  lu.assertEquals(bCar:length(), 3)
  if _VERSION >= 'Lua 5.2' then
    lu.assertEquals(#bCar, 3)
  end

  lu.assertFalse('bmi' == bCar)
  lu.assertFalse(bCar == 'bmi')
end

function Test_decorations_inheritance()
  local Car = createDecoratedClass()
  local Van = class.create(Car)
  local aVan = Van:new('ami')
  lu.assertEquals(tostring(aVan), 'ami')
end

function Test_finalize_gc()
  local count = 0
  local Object = class.create(function(pt)
    function pt:finalize()
      count = count + 1
    end
  end)
  lu.assertEquals(count, 0)
  local object = Object:new()
  lu.assertNotNil(object)
  lu.assertEquals(count, 0)
  object = nil
  collectgarbage('collect')
  lu.assertEquals(count, 1)
end

os.exit(lu.LuaUnit.run())
