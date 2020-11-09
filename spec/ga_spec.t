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
      r = r/b
      assert.equal(r, 3.0f)
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
      var b = GA2.vector(2,4)/GA2.scalar(2)
      assert.equal(b, GA2.vector(1,2))
      var c = GA2i.vector(2,3)*GA2i.scalar(5)
      assert.equal(c, GA2i.vector(10,15))
    end

    do
      var a = GA3.vector(2,3,4)*GA3.scalar(5)
      assert.equal(a, GA3.vector(10,15,20))
      var b = GA3.vector(2,4,8)/GA3.scalar(2)
      assert.equal(b, GA3.vector(1,2,4))
    end

    do
      var a = GA4.vector(2,3,4,5)*GA4.scalar(5)
      assert.equal(a, GA4.vector(10,15,20,25))
      var b = GA4.vector(2,4,8,6)/GA4.scalar(2)
      assert.equal(b, GA4.vector(1,2,4,3))
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

    do
      var a = GA3.vector(2,0,0)*GA3.vector(0,3,0)
      assert.equal(a, GA3.bivector(6,0,0))

      var b = GA3.vector(2,3,4)*GA3.vector(5,6,7)
      assert.equal(b, GA3.scalar(56) - GA3.bivector(3,6,3))
    end

    do
      var a = GA4.vector(2,0,0,0)*GA4.vector(0,3,0,0)
      assert.equal(a, GA4.bivector(6,0,0,0,0,0))

      var b = GA4.vector(2,3,4,5)*GA4.vector(6,7,8,9)
      assert.equal(b, GA4.scalar(110) - GA4.bivector(4,8,4,12,8,4))
    end
  end)

  it('should invert vectors', terra()
    do
      var a = GA1.vector(2)
      var b : float = a * a:inverse()
      assert.near(b, 1.0f)
    end

    do
      var a = GA2.vector(2, 3) + GA2.scalar(4) + GA2.bivector(5)
      var b = a * a:inverse()
      assert.near(b.v[0], 1.0f)
    end

    do
      var a = GA3.vector(2, 2, 2)
      var b = a*a:inverse()
      assert.near(b.v[0], 1.0f)

      var m = GA3.trivector(9)
      var n = m*m:inverse()
      assert.near(n.v[0], 1.0f)

      var u = GA3.bivector(6, 7, 8)
      var v = u*u:inverse()
      assert.near(v.v[0], 1.0f)

      var g = GA3.scalar(9.012345678) + GA3.vector(1.1,2.23,3.456) + GA3.bivector(4.7891,5.23456,6.789012) + GA3.trivector(7.3456789)
      var h = g*g:inverse()
      assert.near(v.v[0], 1.0f)
    end

    do
      var a = GA4.vector(2, 3, 4, 5)
      var b = a*a:inverse()
      assert.near(b.v[0], 1.0f)
      
      --var m = GA4.bivector(2, 3, 4, 5, 6, 7)
      --var n = m*m:inverse()
      --C.printf("%s\n", n:tostring())
      --assert.near(b.v[0], 1.0f)
    end
  end)

  it('should multiply bivectors with scalars', terra()
    do
      var a = GA2.bivector(2)*GA2.scalar(3)
      assert.equal(a, GA2.bivector(6))
    end

    do
      var a = GA3.bivector(3,4,5)*GA3.scalar(2)
      assert.equal(a, GA3.bivector(6,8,10))
    end

    do
      var a = GA4.bivector(3,4,5,6,7,8)*GA4.scalar(2)
      assert.equal(a, GA4.bivector(6,8,10,12,14,16))
    end
  end)

  it('should multiply bivectors with vectors', terra()
    do
      var a = GA2.bivector(2)*GA2.vector(3,4)
      assert.equal(a, GA2.vector(8,-6))
    end

    do
      var a = GA3.bivector(3,4,5)*GA3.vector(6,7,8)
      assert.equal(a, GA3.vector(53,22,-59) + GA3.trivector(26))
    end

    do
      var a = GA4.bivector(3,4,5,6,7,8)*GA4.vector(1,2,9,10)
      assert.equal(a, GA4.vector(102,112,66,-92) + GA4.trivector(24,25,-6,3))
    end
  end)

  it('should multiply bivectors with bivectors', terra()
    do
      var a = GA2.bivector(2)*GA2.bivector(3)
      assert.equal(a, GA2.scalar(-6))
    end

    do
      var a = GA3.bivector(3,4,5)*GA3.bivector(6,7,8)
      assert.equal(a, GA3.scalar(-86) + GA3.bivector(3,-6,3))
    end

    do
      var a = GA4.bivector(3,4,5,6,7,8)*GA4.bivector(9,10,11,12,13,14)
      var c = GA4.scalar(-397) + GA4.bivector(12,0,12,-48,0,24) + GA4.vector4(118)
      assert.truthy(a == c)
    end
  end)

  it('should correctly rotate vectors', terra()
    var PI = 3.14159f

    do
      var i = GA3.bivector(1,0,1):normalize()
      var v = (GA3.exp(-i*(PI/4))*GA3.vector(1,1,1))*GA3.exp(i*(PI/4))
      assert.truthy((v - GA3.vector(0.29289, 0, 1.70711)):magnitude() <= 0.0001f)
    end

    do
      var i = GA3.bivector(1,0,0)
      var v = (GA3.exp(-i*(PI/4))*GA3.vector(1,0,1))*(Math.cos(PI/4) + i*Math.sin(PI/4))
      --var v = ((Math.cos(PI/4) + (-i)*Math.sin(PI/4))*GA3.vector(1,0,1))*(Math.cos(PI/4) + i*Math.sin(PI/4))
      assert.truthy((v - GA3.vector(0, 1, 1)):magnitude() <= 0.00001f)
    end
  end)

  it('should calculate the dot product correctly', terra()
    var f = GA3.bivector(1,2,3)
    -- This must be EXACTLY equal, because it SHOULD be the exact same sequence of float calculations
    assert.equal(f:magnitude(), Math.sqrt(Math.fabs_32(f:dot(f))))
  end)

  it('should calculate the wedge product correctly', terra()
    var f = GA3.bivector(1,2,3)
    assert.equal(f^f, [GA3.multivector({3,5,6})]{array(0.f,0.f,0.f)})
    assert.equal(GA3.vector(1,0,0)^GA3.vector(0,1,0), GA3.bivector(1,0,0))
  end)

  it('should allow accessing components via x/y/z/w', terra()
    var v = GA4.scalar(1) + GA4.vector(2,3,4,5) + GA4.bivector(6,7,8,9,10,11) + GA4.trivector(12,13,14,15) + GA4.vector4(16)
    assert.equal(v.x,2)
    assert.equal(v.y,3)
    assert.equal(v.z,4)
    assert.equal(v.w,5)
    assert.equal(v.xy,6)
    assert.equal(v.xyz,12)
    assert.equal(v.xyzw,16)
  end)

  it('should do grade projection correctly', terra()
    var v = GA4.scalar(1) + GA4.vector(2,3,4,5) + GA4.bivector(6,7,8,9,10,11) + GA4.trivector(12,13,14,15) + GA4.vector4(16)
    assert.equal(v:gradeproj(0), GA4.scalar(1))
    assert.equal(v:gradeproj(1), GA4.vector(2,3,4,5))
    assert.equal(v:gradeproj(2), GA4.bivector(6,7,8,9,10,11))
    assert.equal(v:gradeproj(3), GA4.trivector(12,13,14,15))
    assert.equal(v:gradeproj(4), GA4.vector4(16))
  end)

  it('should project and reject correctly', terra()
    var v = GA3.vector(1,1,1)
    var B = GA3.bivector(1,0,0) -- project on to xy-plane
    assert.equal(v:project(B), GA3.vector(1,1,0))
    assert.equal(v:reject(B), GA3.vector(0,0,1))
  end)

  it('should calculate volume correctly', terra()
    var verts = arrayof(GA3.vector_t, GA3.vector(1,1,0), GA3.vector(2,1,0), GA3.vector(2,2,0), GA3.vector(1,2,0), GA3.vector(1,2,1), GA3.vector(2,2,1), GA3.vector(2,1,1), GA3.vector(1,1,1))
    var origin = GA3.vector(0,0,0)
    var area = escape 
      local function triarea(a,b,c) 
        return `((([origin] - verts[ [a] ])^(verts[ [a] ] - verts[ [b] ])^(verts[ [b] ] - verts[ [c] ]))/3)
      end
      
      emit(`[triarea(0,1,2)] +
        [triarea(0,3,4)] +
        [triarea(0,7,6)] +
        [triarea(3,2,5)] +
        [triarea(6,5,2)] +
        [triarea(7,4,5)])
    end

    assert.equal(area, GA3.trivector(1))
  end)
end)