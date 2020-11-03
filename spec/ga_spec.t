local GA = require 'std.ga'
local GA1 = GA(float, 1)
local GA2 = GA(float, 2)
local GA3 = GA(float, 3)
local GA4 = GA(float, 4)
local GA2i = GA(int, 2)
local Math = require 'std.math'
local C = terralib.includecstring [[#include <stdio.h>]]

describe("Multivector", function()
  it('should calculate the sign correctly', terra()
    assert.equal(GA3.bitsetsign(0,0), 1)
    assert.equal(GA3.bitsetsign(1,0), 1)
    assert.equal(GA3.bitsetsign(0,1), 1)
    assert.equal(GA3.bitsetsign(2,1), -1)
    assert.equal(GA3.bitsetsign(1,2), 1)
    assert.equal(GA3.bitsetsign(3,1), -1)
    assert.equal(GA3.bitsetsign(1,3), 1)
    assert.equal(GA3.bitsetsign(3,2), 1)
    assert.equal(GA3.bitsetsign(2,3), -1)
    assert.equal(GA3.bitsetsign(4,1), -1)
    assert.equal(GA3.bitsetsign(4,2), -1)
    assert.equal(GA3.bitsetsign(4,3), 1)
    assert.equal(GA3.bitsetsign(4,4), 1)
    assert.equal(GA3.bitsetsign(1,4), 1)
    assert.equal(GA3.bitsetsign(2,4), 1)
    assert.equal(GA3.bitsetsign(3,4), 1)
    assert.equal(GA3.bitsetsign(4,4), 1)
    assert.equal(GA3.bitsetsign(5,1), -1)
    assert.equal(GA3.bitsetsign(6,1), 1)
    assert.equal(GA3.bitsetsign(7,1), 1)
    assert.equal(GA3.bitsetsign(1,5), 1)
    assert.equal(GA3.bitsetsign(1,6), 1)
    assert.equal(GA3.bitsetsign(1,7), 1)
    assert.equal(GA3.bitsetsign(7,3), -1)
  end)

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
      --r = r/b
      --assert.equal(r, 3.0f)
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
      var a = GA2.vector(2,0)*GA2.vector(0,3)
      assert.equal(a, GA2.bivector(6))

      var b = GA2.vector(2,3)*GA2.vector(4,5)
      assert.equal(b, GA2.scalar(23) - GA2.bivector(2))
    end
  end)

  --[[it('should invert vectors', terra()
    do
      var a = GA1.vector(2)
      var c = a:dot(a)
      C.printf("%s", c:tostring())
      a = a:inverse()
      C.printf("%s", a:tostring())
      var b = GA1.vector(2) * a
      C.printf("%s", b:tostring())
    end

    do
      var a = GA2.vector(2, 2)
      var b = a:inverse()
      C.printf("%s", (a*b):tostring())
    end

    do
      var a = GA3.vector(2, 2, 2)
      var b = a:inverse()
      C.printf("%s", (a*b):tostring())
    end
  end)]]

  it('should multiply bivectors with scalars', terra()
  end)

  it('should multiply bivectors with vectors', terra()

  end)

  it('should multiply bivectors with bivectors', terra()

  end)

  it('should correctly rotate vectors', terra()
    var PI = 3.14159f

    --[[do
      var i = GA3.bivector(1,0,1):normalize()
      var v = (GA3.exp(-i*(PI/4))*GA3.vector(1,1,1))*GA3.exp(i*(PI/4))
      assert.truthy((v - GA3.vector(0.29289, 0, 1.70711)):norm() <= 0.0001f)
    end]]

    do
      var i = GA3.bivector(1,0,0)
      var v = (GA3.exp(-i*(PI/4))*GA3.vector(1,0,1))*(Math.cos(PI/4) + i*Math.sin(PI/4))
      --var v = ((Math.cos(PI/4) + (-i)*Math.sin(PI/4))*GA3.vector(1,0,1))*(Math.cos(PI/4) + i*Math.sin(PI/4))
      assert.truthy((v - GA3.vector(0, 1, 1)):norm() <= 0.00001f)
    end
  end)

  it('should calculate the dot product correctly', terra()
    var f = GA3.bivector(1,2,3)
    -- This must be EXACTLY equal, because it SHOULD be the exact same sequence of float calculations
    assert.equal(f:norm(), Math.sqrt(Math.fabs_32(f:dot(f))))
  end)

  it('should calculate the wedge product correctly', terra()
    var f = GA3.bivector(1,2,3)
    assert.equal(f^f, [GA3.multivector({3,5,6})]{array(0.f,0.f,0.f)})
    assert.equal(GA3.vector(1,0,0)^GA3.vector(0,1,0), GA3.bivector(1,0,0))
  end)

  it('should calculate volume correctly', terra()
    
  end)
end)