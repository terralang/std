local GA = require 'std.ga'
local GA1 = GA(float, 1)
local GA2 = GA(float, 2)
local GA3 = GA(float, 3)
local GA4 = GA(float, 4)
local GA2i = GA(int, 2)

describe("Multivector", function()
  it('should be convertible to and from scalars', terra()
    do
      var a : GA1.multivector({0}) = 3.0
      var r : float = a*2
      assert.equal(r, 6.0f)
      var b = [GA4.multivector({0})]{array(-3.0f)}
      r = a*b
      assert.equal(r, -9.0f)
    end

    do
      var a = GA1.scalar(3)
      var r : float = a*2
      assert.equal(r, 6.0f)
      var b = GA4.scalar(-3.0f)
      r = a*b
      assert.equal(r, -9.0f)
    end
  end)

  it('should multiply vectors with scalars', terra()
    do
      var a = GA1.vector(2)*GA1.scalar(-3)
      assert.equal(a, GA1.vector(-6.0f))
    end

    do
      var a = GA2.vector(2,3)*GA2.scalar(5)
      assert.equal(a, GA2.vector(10,15))
      --var b = GA2.vector(2,4)/GA2.scalar(2)
      --assert.equal(b, GA2.vector(1,2))
      var c = GA2i.vector(2,3)*GA2i.scalar(5)
      assert.equal(c, GA2i.vector(10,15))
    end

    do
      var a = GA3.vector(2,3,4)*GA3.scalar(5)
      assert.equal(a, GA3.vector(10,15,20))
      --var b = GA3.vector(2,4,8)/GA3.scalar(2)
      --assert.equal(b, GA3.vector(1,2,4))
    end

    do
      var a = GA4.vector(2,3,4,5)*GA4.scalar(5)
      assert.equal(a, GA4.vector(10,15,20,25))
      --var b = GA4.vector(2,4,8,6)/GA4.scalar(2)
      --assert.equal(b, GA4.vector(1,2,4,3))
    end
  end)

  it('should multiply vectors with vectors', terra()
    do
      var a : float = GA1.vector(2)*GA1.vector(3)
      assert.equal(a, 6.0f)
    end

    do
      --var a : float = GA2.vector(2,0)*GA2.vector(0,3)
      --assert.equal(a, 0.0f)

      --var b = GA2.vector(2,3)*GA2.vector(4,5)
      --assert.equal(b, GA2.scalar(23) - GA2.bivector(2))
    end
  end)

  it('should multiply bivectors with scalars', terra()

  end)

  it('should multiply bivectors with vectors', terra()

  end)

  it('should multiply bivectors with bivectors', terra()

  end)
end)