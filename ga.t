local tableintersect = require 'std.meta.tableintersect'
local tableunion = require 'std.meta.tableunion'
local bits = require 'std.bit'
local String = require 'std.string'
local Math = require 'std.math'
local G = {}
local multivector
local memoize = {}
local memovalues = {}
local C = terralib.includecstring [[#include <stdio.h>]]

local terra countbits(x : int) : int return bits.ctpop(x) end

local terra bitsetsign(xs : int, ys : int) : int
  var swapcount = 0
  var bscan = 0
  xs = xs >> 1
  while xs ~= 0 or ys ~= 0 do
    bscan = bscan + (ys and 1) -- current count of unique basis in ys
    swapcount = swapcount + ((xs and 1) * bscan)
    xs = xs >> 1
    ys = ys >> 1
  end
  return terralib.select(swapcount % 2 == 0, 1, -1)
end

local function getbasis(x)
  x = x:gettype().metamethods.basis
  if not x then
    error(tostring(x) .. " is not a multivector!")
  end
  return x
end

local function prettycomponent(x) 
  local r = "e"
  for i = 0,31 do
    if bit.band(x,2^i) ~= 0 then
      r = r .. tostring(i)
    end
  end
  return r
end

local function divide(x,y)
  local values = {}
  for i=0,x:gettype().metamethods.N-1 do
    table.insert(values, `x.v[i] / y)
  end
  return `[x:gettype()]{array(values)}
end

multivector = function(T, Components)
  -- we sort the components before memoizing the function
  table.sort(Components)
  local memokey = memoize[T]
  if not memokey then
    memokey = {}; memoize[T] = memokey
  end
  for i,v in ipairs(Components) do
    local n = memokey[v]
    if not n then
      n = {}; memokey[v] = n
    end
    memokey = n
  end
  if memovalues[memokey] then
    return memovalues[memokey]  
  end

  local struct s {
    v : T[#Components]
  }

  memovalues[memokey] = s
  s.metamethods.type = T
  s.metamethods.basis = {}
  for i,v in ipairs(Components) do
    if type(v) ~= "number" then
      error("Expected a number but found "..type(v))
    end
    s.metamethods.basis[v] = i - 1
  end

  s.metamethods.N = #Components
  local N = #Components
  
  s.metamethods.set = 0
  for k,v in pairs(s.metamethods.basis) do
    s.metamethods.set = bit.bor(s.metamethods.set, k)
  end

  s.metamethods.__typename = function(self)
    local grade = countbits(self.metamethods.set)
    if grade == 0 then
      return ("Scalar<%s>"):format(tostring(self.metamethods.type))
    end

    local prettybasis = {}
    for i,v in ipairs(Components) do
      table.insert(prettybasis, prettycomponent(v))
    end

    return ("%d-Vector(%s)<%s>"):format(grade, table.concat(prettybasis, "+"), tostring(self.metamethods.type))
  end

  terra s:length() : T
    escape
      local acc = `[T](0)
      for i = 0,N-1 do
        acc = `[acc] + self.v[i]*self.v[i]
      end
      if T == float then
        emit(quote return Math.sqrt_32(acc) end)
      else
        emit(quote return Math.sqrt_64([double](acc)) end)
      end
    end
  end

  terra s:normalize() : s
    var length = self:length()
    var normalized : s
    escape
      for i = 0,N-1 do
        emit(quote normalized.v[i] = self.v[i] / length end)
      end
    end
    return normalized
  end

  -- The norm of an arbitrary multivector is itself times it's own conjugate, but this reduces to just (-1)^k x_i^2, where k is the grade of the component.
  terra s:norm() : T
    escape
      local acc = `0
      for k,i in pairs(s.metamethods.basis) do
        if (countbits(k) % 2) ~= 0 then
          acc = `[acc] - self.v[i]*self.v[i]
        else
          acc = `[acc] + self.v[i]*self.v[i]
        end
      end
      emit(quote return acc end)
    end
  end

  terra s:basis() : int 
    return [s.metamethods.set]
  end

  terra s:grade() : int
    return countbits([s.metamethods.set])
  end

  local function convertscalar(x)
    if x:gettype():isarithmetic() then
      return `[multivector(T, {0})](x)
    end
    return x
  end

  local function product(x, y, check)
    if x == nil or y == nil then
      error("Cannot pass nil into product!")
    end
    x = convertscalar(x)
    y = convertscalar(y)
    local xbasis = getbasis(x)
    local ybasis = getbasis(y)
    -- multiply every component with every other component, only keep ones that satisfy check()
    local results = {}
    --local debugging = {}
    for xb,xi in pairs(xbasis) do
      for yb,yi in pairs(ybasis) do
        local basis = bit.bxor(xb,yb)
        if check(basis,xb,yb) then
          if results[basis] == nil then
            results[basis] = `0
          end
          --table.insert(debugging, quote C.printf(["%g" .. xi .. "_" ..  prettycomponent(xb) .. "|" .. xb .. " * %g".. yi .. "_" .. prettycomponent(yb).. "|" .. yb  .." = (" .. bitsetsign(xb, yb) .. ")%g_" .. prettycomponent(basis) .. "\n"], x.v[xi], y.v[yi], x.v[xi]*y.v[yi]) end)
          results[basis] = `[ results[basis] ] + [bitsetsign(xb, yb)]*x.v[xi]*y.v[yi]
        end
      end
    end

    local components = {}
    for k,v in pairs(results) do table.insert(components, k) end
    return quote
      var m : multivector(T, components)
      escape
        --for i,v in ipairs(debugging) do emit(v) end
        local basis = m.type.metamethods.basis
        for k,q in pairs(results) do
          emit(quote m.v[ [basis[k]] ] = [q] end)
        end
      end
    in
      m
    end
  end

  -- Dot product only keeps components with the same grade
  s.methods.dot = macro(function(x, y) return product(x,y, function(basis, xb, yb) return countbits(basis) == (countbits(yb) - countbits(xb)) end) end)
  -- Wedge product keeps all components that aren't in the dot product
  s.methods.wedge = function(x, y) return product(x,y, function(basis, xb, yb) return countbits(basis) ~= (countbits(yb) - countbits(xb)) end) end
  
  s.metamethods.__xor = macro(function(self, v) return s.methods.wedge(self,v) end)
  s.methods.wedge = macro(s.methods.wedge, s.methods.wedge)

  terra s.metamethods.__eq(a : &s, b : &s) : bool
    -- Because a and b are the same type, all the component basis vectors must match
    escape
      local acc = `true
      for i = 0,N-1 do
        acc = `[acc] and (a.v[i] == b.v[i])
      end
      emit(quote return [acc] end)
    end
  end

  terra s.metamethods.__ne(a : &s, b : &s) : bool
    return not [s.metamethods.__eq](a, b)
  end

  terra s.metamethods.__unm(a : &s): s
    var res: s
    escape
      for i = 0, N-1 do
        emit(quote res.v[i] = -a.v[i] end)
      end
    end
    return res
  end

  s.metamethods.__add = macro(function(x, y)
    x = convertscalar(x)
    y = convertscalar(y)
    local xbasis = getbasis(x)
    local ybasis = getbasis(y)

    local components = {}
    tableunion(xbasis, ybasis, function(k) table.insert(components, k) end)
    local tresult = multivector(T, components)
    return quote
      var m : tresult
      escape
        for k,i in pairs(tresult.metamethods.basis) do
          if not xbasis[k] then
            emit(quote m.v[i] = y.v[ [ybasis[k]] ] end)
          elseif not ybasis[k] then
            emit(quote m.v[i] = x.v[ [xbasis[k]] ] end)
          else
            emit(quote m.v[i] = x.v[ [xbasis[k]] ] + y.v[ [ybasis[k]] ] end)
          end
        end
      end
    in
      m
    end
  end)

  s.metamethods.__sub = macro(function(x, y) return `x + (-y) end)
  s.metamethods.__mul = macro(function(x, y) return product(x, y, function() return true end) end)

  -- Performs a clifford conjugation: https://math.stackexchange.com/questions/3459273/why-is-the-clifford-conjugate-and-norm-defined-the-way-it-is
  terra s:conjugate() : s
    var v : s = @self
    escape
      for k,i in pairs(s.metamethods.basis) do
        local grade = countbits(k)
        if (grade % 2) ~= 0 then
          emit(quote v.v[i] = -v.v[i] end)
        end
        if ((grade * (grade-1))/2) ~= 0 then
          emit(quote v.v[i] = -v.v[i] end)
        end
      end
    end
    return v
  end

  -- Performs just a reversion
  terra s:reversion() : s
    var v : s = @self
    escape
      for k,i in pairs(s.metamethods.basis) do
        local grade = countbits(k)
        if ((grade * (grade-1))/2) ~= 0 then
          emit(quote v.v[i] = -v.v[i] end)
        end
      end
    end
    return v
  end

  s.metamethods.__div = macro(function(x,y)
    x = convertscalar(x)
    y = convertscalar(y)
    if y:gettype().metamethods.N == 1 and y:gettype().metamethods.basis[0] == 0 then
      return divide(x, `y.v[0])
    else
      return `x * y:inverse()
    end
  end)

  s.metamethods.__cast = function(from, to, exp)
    if from:isarithmetic() and to == s and s.metamethods.N == 1 and s.metamethods.basis[0] == 0 then
      return `s{array([T]([exp]))}
    end
    if from == s and to:isarithmetic() and s.metamethods.N == 1 and s.metamethods.basis[0] == 0 then
      return `[to]([exp].v[0])
    end
    error(("unknown conversion %s to %s"):format(tostring(from),tostring(to)))
  end

  -- TODO: implement proper 3rd dimension inverse using the reversion: http://repository.essex.ac.uk/19733/1/MVInverse_rv_14Feb2017.pdf
  terra s:inverse() : s
    --var n = @self * self:conjugate()
    --return [divide(`self:conjugate(), `n.v[0])]
    var n = self:norm()
    return [divide(`self:conjugate(), `n)]
    -- For 3D:
    -- var n = self:norm() -- this is self * self:conjugate()
    -- var r = n:reversion()
    -- var nr = n*r
    -- return [divide(`self:conjugate() * r, `nr.v[0])]
  end
  
  s.methods.tostring = macro(function(self)
    local str = ""
    for i=1,N do str = str .. "%g_" .. prettycomponent(Components[i]) .. " " end
    local args = {}
    for i=0,N-1 do table.insert(args, `self.v[ [i] ]) end
    return `String.Format([str], [args])
  end)

  return memovalues[memokey]
end

-- This function represents a parameterized GA vector space of type T and dimensions N, which then contains appropriate basis elements and vector/bivector constructors
function GA(T, N)
  local ga = {}
  terra ga.scalar(a : T) : multivector(T, {0}) return a end

  local kvectors = {}
  for i = 0,N-1 do
    ga["e"..i] = multivector(T, {2^i})
    table.insert(kvectors, {})
  end

  -- generates a table for all possible multivector components to get the k-vector at that grade
  for i = 1,(2^N)-1 do
    table.insert(kvectors[countbits(i)], i)
  end

  for i = 1,N do
    ga["vector"..i] = macro(function(...)
      if select("#", ...) ~= #kvectors[i] then
        error("Expected exactly "..#kvectors[i].." arguments for this "..i.."-vector!")
      end
      local args = {...}
      local components = {}
      local values = {}

      -- Only include basis vectors for non-zero elements
      for k,v in ipairs(args) do
        if not (terralib.isquote(v) and v:gettype():isarithmetic() and v:asvalue() == 0) then
          table.insert(components, kvectors[i][k])
          table.insert(values, `[T]([v]))
        end
      end

      return `[multivector(T, components)]{array([values])}
    end)
  end

  ga.exp = macro(function(v)
    return quote
      var i = v:normalize()
      var th = v:length()
    in
      (Math.cos(th) + i*Math.sin(th))
    end
  end)
  
  -- pretty name aliases
  if ga.vector1 ~= nil then ga.vector = ga.vector1 end
  if ga.vector2 ~= nil then ga.bivector = ga.vector2 end
  if ga.vector3 ~= nil then ga.trivector = ga.vector3 end
  if ga.vector4 ~= nil then ga.quadvector = ga.vector4 end

  ga.bitsetsign = bitsetsign
  ga.multivector = macro(function(c) return multivector(T, c) end, function(c) return multivector(T, c) end)
  ga.PS = `[multivector(T, kvectors[N])]{array([T](1))}
  ga.invPS = `[multivector(T, kvectors[N])]{array([T](1))}
  
  return ga
end

return macro(GA, GA)