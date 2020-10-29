local tableintersect = require 'std.meta.tableintersect'
local tableunion = require 'std.meta.tableunion'
local bits = require 'std.bit'
local G = {}
local multivector
local memoize = {}
local memovalues = {}

multivector = function(ty, c)
  local inner = function(T, Components)
    local struct s {
      v : T[#Components]
    }

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
    
    local terra countbits(x : int) : int return bits.ctpop(x) end

    s.metamethods.__typename = function(self)
      local grade = countbits(self.metamethods.set)
      if grade == 0 then
        return ("Scalar<%s>"):format(tostring(self.metamethods.type))
      end

      local prettybasis = {}
      for i,v in ipairs(Components) do
        local r = "e"
        for i = 0,N-1 do
          if b and (2^i) then
            r = r .. tostring(i)
          end
        end
        table.insert(prettybasis, r)
      end

      return ("%d-Vector(%s)<%s>"):format(grade, table.concat(prettybasis, "+"), tostring(self.metamethods.type))
    end

    local function getbasis(x)
      x = x:gettype().metamethods.basis
      if not x then
        error(tostring(x) .. " is not a multivector!")
      end
      return x
    end

    local function convertscalar(x)
      if x:gettype():isarithmetic() then
        return `[multivector(T, {0})](x)
      end
      return x
    end

    local terra bitsetsign(a : int, b : int) : int
      var swapcount = 0
      var bscan = 0
      while a ~= 0 and b ~= 0 do
        swapcount = swapcount + ((a and 1) * bscan)
        bscan = bscan + (b and 1)
        a = a >> 1
        b = b >> 1
      end
      return terralib.select(bscan % 2 == 0, 1, -1)
    end

    terra s:norm() : T
      escape
        local acc = `0
        for i = 0,N-1 do
          acc = `[acc] + self.v[i]*self.v[i]
        end
        return acc
      end
    end

    terra s:normalize() : s
      var length = self:norm()
      var normalized : s
      escape
        for i = 0,N-1 do
          emit(quote normalized.v[i] = self.v[i] / length end)
        end
      end
      return normalized
    end

    terra s:basis() : int 
      return [s.metamethods.set]
    end

    terra s:grade() : int
      return bits.ctpop([s.metamethods.set])
    end

    s.methods.dot = macro(function(self, b)
      local basis = b:gettype().metamethods.basis
      if not basis then
        error(tostring(b) .. " is not a multivector!")
      end

      local acc = `0
      tableintersect(s.metamethods.basis, basis, function(k)
        acc = `[acc] + self.v[ [s.metamethods.basis[k]] ]*b.v[ [basis[k]] ]
      end)
      return acc
    end)

    terra s.metamethods.__eq(a : s, b : s) : bool
      -- Because a and b are the same type, all the component basis vectors must match
      escape
        local acc = `true
        for i = 0,N-1 do
          acc = `[acc] and (a.v[i] == b.v[i])
        end
        emit(quote return [acc] end)
      end
    end

    terra s.metamethods.__ne(a : s, b : s) : bool
      return not [s.metamethods.__eq](a, b)
    end

    terra s.metamethods.__unm(a : s): s
      var res: s
      escape
        for i = 0, N-1 do
          emit(quote res.v[i] = -a.v[i] end)
        end
      end
      return res
    end
    
    -- wedge product (turned into a macro below)
    s.methods.wedge = function(a, b)

    end
    
    s.metamethods.__xor = macro(function(self, v) return s.methods.wedge(self,v) end)
    s.methods.wedge = macro(s.methods.wedge)

    s.metamethods.__add = macro(function(x, y)
      x = convertscalar(x)
      y = convertscalar(y)
      local xbasis = getbasis(x)
      local ybasis = getbasis(y)

      local components = {}
      tableunion(xbasis, ybasis, function(k) table.insert(components, k) end)
      return quote
        var m : multivector(T, components)
        escape
          for k,i in pairs(m:gettype().metamethods.basis) do
            if not xbasis[k] then
              emit(quote m.v[i] = y.v[ybasis[k]] end)
            elseif not ybasis[k] then
              emit(quote m.v[i] = x.v[xbasis[k]] end)
            else
              emit(quote m.v[i] = x.v[xbasis[k]] + y.v[ybasis[k]] end)
            end
          end
        end
      in
        m
      end
    end)

    s.metamethods.__sub = macro(function(x, y) return `x + (-y) end)
    
    s.metamethods.__mul = macro(function(x, y)
      x = convertscalar(x)
      y = convertscalar(y)
      local xbasis = getbasis(x)
      local ybasis = getbasis(y)
      -- multiply every component with every other component
      local results = {}
      for xb,xi in pairs(xbasis) do
        for yb,yi in pairs(ybasis) do
          local basis = bit.bxor(xb,yb)
          if results[basis] == nil then
            results[basis] = `0
          end
          results[basis] = `[results[basis]] + [bitsetsign(xb, yb)]*x.v[xi]*y.v[yi]
        end
      end

      local components = {}
      for k,v in pairs(results) do table.insert(components, k) end
      return quote
        var m : multivector(T, components)
        escape
          local basis = m.type.metamethods.basis
          for k,q in pairs(results) do
            emit(quote m.v[ [basis[k]] ] = [q] end)
          end
        end
      in
        m
      end
    end)

    terra s:conjugate() : s

    end

    terra s:inverse() : s
      --return -self:normalize()
    end
    
    s.metamethods.__div = macro(function(x, y) return `x * y:inverse() end)
    
    s.metamethods.__cast = function(from, to, exp)
      if from:isarithmetic() and to == s and s.metamethods.N == 1 and s.metamethods.basis[0] == 0 then
        return `s{array([T]([exp]))}
      end
      if from == s and to:isarithmetic() and s.metamethods.N == 1 and s.metamethods.basis[0] == 0 then
        return `[to]([exp].v[0])
      end
      error(("unknown conversion %s to %s"):format(tostring(from),tostring(to)))
    end

    return s
  end

  -- we sort the components before calling the memoized function so we get the same type out
  table.sort(c)
  local key = memoize[ty]
  if not key then
    key = {}; memoize[ty] = key
  end
  for i,v in ipairs(c) do
    local n = key[v]
    if not n then
      n = {}; key[v] = n
    end
    key = n
  end
  if not memovalues[key] then
    memovalues[key] = inner(ty, c)
  end
  return memovalues[key]
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

  local terra countbits(a : int) : int return bits.ctpop(a) end

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

  -- pretty name aliases
  if ga.vector1 ~= nil then ga.vector = ga.vector1 end
  if ga.vector2 ~= nil then ga.bivector = ga.vector2 end
  if ga.vector3 ~= nil then ga.trivector = ga.vector3 end
  if ga.vector4 ~= nil then ga.quadvector = ga.vector4 end

  ga.multivector = macro(function(c) return multivector(T, c) end, function(c) return multivector(T, c) end)
  return ga
end

return macro(GA, GA)