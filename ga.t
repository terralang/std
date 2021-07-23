local tableunion = require 'std.meta.tableunion'
local bits = require 'std.bit'
local String = require 'std.string'
local Math = require 'std.math'
local memoize = {}
local memovalues = {}

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
  local b = x.metamethods.basis
  if not b then
    error(tostring(x) .. " is not a multivector!")
  end
  return b
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
  if x:gettype().metamethods.N > 0 then
    for i=0,x:gettype().metamethods.N-1 do
      table.insert(values, `x.v[i] / y)
    end
    return `[x:gettype()]{array(values)}
  end
  return `x
end

local lookups = { x = 1, y = 2, z = 4, w = 8 }
function swizzlebasis(entryname)
  local basis = 0
  for i=1,#entryname do

    local e = lookups[entryname:sub(i,i)]
    if e then
      basis = bit.bor(basis, e)
    else
      error (entryname:sub(i,i).." is not a valid component.")
    end
  end
  return basis
end

function entrymissing(entryname, expr)
  local index = expr:gettype().metamethods.basis[swizzlebasis(entryname)]
  if index then
    return `expr.v[ [index] ]
  else
    error("Tried to look up basis that doesn't exist in an "..expr:gettype().metamethods.grade.."-dimensional vector.")
  end
end
  
local function setentry(entryname, expr, value)
  local index = expr:gettype().metamethods.basis[swizzlebasis(entryname)]
  if index then
    return quote expr.v[ [index] ] = value end
  else
    error("Tried to set basis that doesn't exist in an "..expr:gettype().metamethods.grade.."-dimensional vector.")
  end
end

local function typename(self)
  if self.metamethods.N == 0 then
    return "Zero"
  end
  
  if self.metamethods.grade == 0 then
    return ("Scalar<%s>"):format(tostring(self.metamethods.type))
  end

  local prettybasis = {}
  for v,i in pairs(self.metamethods.basis) do
    table.insert(prettybasis, prettycomponent(v))
  end

  return ("%d-Vector(%s)<%s>"):format(self.metamethods.grade, table.concat(prettybasis, "+"), tostring(self.metamethods.type))
end

-- To keep compile times down, we have to split out declaring the type with filling it out.
local function mv(T, Components)
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

  s.metamethods.type = T
  s.metamethods.N = #Components
  s.metamethods.components = Components
  s.metamethods.basis = {}
  for i,v in ipairs(Components) do
    if type(v) ~= "number" then
      error("Expected a number but found "..type(v))
    end
    s.metamethods.basis[v] = i - 1
  end
  
  s.metamethods.set = 0
  for k,v in pairs(s.metamethods.basis) do
    s.metamethods.set = bit.bor(s.metamethods.set, k)
  end
  s.metamethods.grade = countbits(s.metamethods.set)
  memovalues[memokey] = s
  return s
end

local function convertscalar(x, T)
  if x:gettype():isarithmetic() then
    return `[mv(T, {0})](x)
  end
  return x
end

function checkbasiseq(basis, xb, yb) return countbits(basis) == (countbits(yb) - countbits(xb)) end
function checkbasisneq(basis, xb, yb) return countbits(basis) ~= (countbits(yb) - countbits(xb)) end
function checktrue(basis, xb, yb) return true end

local productinner = terralib.memoize(function(xt, yt, check, T)
  return terra(x : xt, y : yt)
    escape
      local xbasis = getbasis(xt)
      local ybasis = getbasis(yt)
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
      emit(quote 
        var m : mv(T, components)
        escape
          --for i,v in ipairs(debugging) do emit(v) end
          local basis = m.type.metamethods.basis
          for k,q in pairs(results) do
            emit(quote m.v[ [basis[k]] ] = [q] end)
          end
        end
        return m
      end)
    end
  end

end)

function addinner(xt, yt)
  local xbasis = getbasis(xt)
  local ybasis = getbasis(yt)
  local components = {}
  tableunion(xbasis, ybasis, function(k) table.insert(components, k) end)
  local tresult = mv(xt.metamethods.type, components)
  return terra(x : xt, y : yt) : tresult
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
    return m
  end
end

local multivector

local product = function(x, y, check, T)
  if x == nil or y == nil then
    error("Cannot pass nil into product!")
  end
  x = convertscalar(x, T)
  y = convertscalar(y, T)
  local fn = productinner(x:gettype(), y:gettype(), check, T)
  multivector(fn.type.returntype.metamethods.type,fn.type.returntype.metamethods.components)
  return `[fn](x,y)
end

multivector = function(T, Components)
  local s = mv(T, Components)
  if s.metamethods.__typename then
    return s
  end
  s.metamethods.__typename = typename
  local N = s.metamethods.N

  -- The absolute magnitude used to normalize multivectors.
  terra s:magnitude() : T
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
  terra s:mag2() : T
    escape
      local acc = `[T](0)
      for i = 0,N-1 do
        acc = `[acc] + self.v[i]*self.v[i]
      end
      emit(quote return acc end)
    end
  end

  terra s:normalize() : s
    var magnitude = self:magnitude()
    var normalized : s
    escape
      for i = 0,N-1 do
        emit(quote normalized.v[i] = self.v[i] / magnitude end)
      end
    end
    return normalized
  end

  local function component_op(op, U)
    return terra (self : &s, y : U) : s
      var x : s = @self
      for i = 0,N-1 do
        escape
          if U == s then
            emit(quote x.v[i] = operator(op, x.v[i], y.v[i]) end)
          else
            emit(quote x.v[i] = operator(op, x.v[i], y) end)
          end
        end
      end
      return x
    end
  end

  local ops = { "sub","add","mul","div" }
  for i, op in ipairs(ops) do
    s.methods["component_" .. op] = terralib.overloadedfunction("component_" .. op, {
      component_op("__" .. op, s),
      component_op("__" .. op, T)
      }
    )
  end

  -- The norm of an arbitrary multivector is itself times it's own conjugate, but we only have an efficient implementation up to 3 dimensions
  s.methods.norm = macro(function(self)
      local acc = `[T](0)
      for k,i in pairs(s.metamethods.basis) do
        local count = countbits(k)
          if ((count % 2)) ~= 0 then
            acc = `[acc] - self.v[i]*self.v[i]
          else
            acc = `[acc] + self.v[i]*self.v[i]
          end
      end
      local e012 = nil
      if s.metamethods.basis[0] and s.metamethods.basis[1+2+4] then if not e012 then e012 = `0 end e012 = `[e012] + 2*self.v[ [s.metamethods.basis[0]] ]*self.v[ [s.metamethods.basis[1+2+4]] ] end
      if s.metamethods.basis[1+2] and s.metamethods.basis[4] then if not e012 then e012 = `0 end e012 = `[e012] - 2*self.v[ [s.metamethods.basis[1+2]] ]*self.v[ [s.metamethods.basis[4]] ] end
      if s.metamethods.basis[1+4] and s.metamethods.basis[2] then if not e012 then e012 = `0 end e012 = `[e012] + 2*self.v[ [s.metamethods.basis[1+4]] ]*self.v[ [s.metamethods.basis[2]] ] end
      if s.metamethods.basis[2+4] and s.metamethods.basis[1] then if not e012 then e012 = `0 end e012 = `[e012] - 2*self.v[ [s.metamethods.basis[2+4]] ]*self.v[ [s.metamethods.basis[1]] ] end
      if e012 then
        return `[multivector(T, {0, 1+2+4})]{array([acc], [e012])}
      end

      return `[multivector(T, {0})]{array([acc])}
  end)

  terra s:basis() : int 
    return [s.metamethods.set]
  end

  terra s:grade() : int
    return [s.metamethods.grade]
  end

  -- Dot product only keeps components with the same grade
  s.methods.dot = macro(function(x, y) return product(x,y, checkbasiseq, T) end)
  -- Wedge product keeps all components that aren't in the dot product
  s.methods.wedge = function(x, y) return product(x,y, checkbasisneq, T) end
  
  s.metamethods.__xor = macro(function(self, v) return s.methods.wedge(self,v) end)
  s.methods.wedge = macro(s.methods.wedge, s.methods.wedge)
  s.metamethods.__entrymissing = macro(entrymissing)
  s.metamethods.__setentry = macro(setentry)

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
    x = convertscalar(x, T)
    y = convertscalar(y, T)
    local fn = addinner(x:gettype(), y:gettype())
    multivector(fn.type.returntype.metamethods.type,fn.type.returntype.metamethods.components)
    return `[fn](x,y)    
  end)

  s.metamethods.__sub = macro(function(x, y) return `x + (-y) end)
  s.metamethods.__mul = macro(function(x, y) return product(x, y, checktrue, T) end)

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

  -- Negates grades 3 and 4
  local terra negate34(self : &s) : s
    var v : s = @self
    escape
      for k,i in pairs(s.metamethods.basis) do
        local grade = countbits(k)
        if grade == 3 or grade == 4 then
          emit(quote v.v[i] = -v.v[i] end)
        end
      end
    end
    return v
  end

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

  s.methods.gradeproj = macro(function(self, n)
    local components = {}
    local values = {}
    for b,i in pairs(s.metamethods.basis) do
      if countbits(b) == n:asvalue() then
        table.insert(components, b)
        table.insert(values, `self.v[ [i] ])
      end
    end
    return `[multivector(T, components)]{array([values])}
  end)

  s.methods.project = macro(function(self, B) return `(self:dot(B))/B end)
  s.methods.reject = macro(function(self, B) return `(self:wedge(B))/B end)

  s.metamethods.__div = macro(function(x,y)
    x = convertscalar(x, T)
    y = convertscalar(y, T)
    if y:gettype().metamethods.N == 1 and y:gettype().metamethods.basis[0] == 0 then
      return divide(x, `y.v[0])
    else
      return `x * y:inverse()
    end
  end)

  s.metamethods.__cast = function(from, to, exp)
    if from:isarithmetic() and (to == s or to == &s) and s.metamethods.N == 1 and s.metamethods.basis[0] == 0 then
      return `s{array([T]([exp]))}
    end
    if (from == s or from == &s) and to:isarithmetic() and s.metamethods.N == 1 and s.metamethods.basis[0] == 0 then
      return `[to]([exp].v[0])
    end

    if from:ispointer() then
      from = from.type
    end
    local isptr = to:ispointer() 
    if isptr then
      to = to.type
    end

    if not from.metamethods.basis or not to.metamethods.basis then
      error(("unknown conversion %s to %s"):format(tostring(from),tostring(to)))
    end
  
    local args = {}
    for k,v in pairs(from.metamethods.basis) do
      if not to.metamethods.basis[k] then
        error(("%s does not have %s element from %s"):format(tostring(to), prettycomponent(k), tostring(from)))  
      end
    end
    for i,v in ipairs(to.metamethods.components) do
      local index = from.metamethods.basis[v]
      if not index then
        table.insert(args, `[T](0))
      else
        table.insert(args, `[exp].v[ [index] ])
      end
    end
    if isptr then
      return quote var m = [to]{array([args])} in &m end
    end
    return `[to]{array([args])}
  end
  
  s.methods.tostring = macro(function(self)
    local str = ""
    for i=1,N do str = str .. "%g_" .. prettycomponent(Components[i]) .. " " end
    local args = {}
    for i=0,N-1 do table.insert(args, `self.v[ [i] ]) end
    return `String.Format([str], [args])
  end)

  -- TODO: implement proper 4D inverse using the reversion: http://repository.essex.ac.uk/19733/1/MVInverse_rv_14Feb2017.pdf
  terra s:inverse()
    --var n = @self * self:conjugate()
    var n = self:norm()
    escape
      if n.type == multivector(T,{0}) then
        emit(quote return [divide(`self:conjugate(), `n.v[0])] end)
      else
        emit(quote
          var r = n:reversion()
          var nr = n*r
          var sr = self:conjugate() * r
          return [divide(`sr, `nr.v[0])]
        end)
      end
    end
  end

  return s
end

-- This function represents a parameterized GA vector space of type T and dimensions N, which then contains appropriate basis elements and vector/bivector constructors
function GA(T, N)
  local ga = {}
  terra ga.scalar(a : T) : multivector(T, {0}) return a end
  ga.zero = constant(`[multivector(T, {})]{})

  local kvectors = {}
  for i = 0,(2^N)-1 do
    ga[prettycomponent(i)] = constant(`[multivector(T, {i})]{array([T](1))})
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

      if #values > 0 then
        return `[multivector(T, components)]{array([values])}
      end
      return `[multivector(T, components)]{}
    end)
    ga["vector"..i.."_t"] = multivector(T, kvectors[i])
  end

  ga.exp = macro(function(v)
    return quote
      var i = v:normalize()
      var th = v:magnitude()
    in
      (Math.cos(th) + i*Math.sin(th))
    end
  end)
  
  -- pretty name aliases
  ga.scalar_t = T
  if ga.vector1 ~= nil then ga.vector = ga.vector1; ga.vector_t = ga.vector1_t end
  if ga.vector2 ~= nil then ga.bivector = ga.vector2; ga.bivector_t = ga.vector2_t end
  if ga.vector3 ~= nil then ga.trivector = ga.vector3; ga.trivector_t = ga.vector3_t end
  if ga.vector4 ~= nil then ga.quadvector = ga.vector4; ga.quadvector_t = ga.vector4_t end

  ga.bitsetsign = bitsetsign
  ga.multivector = macro(function(c) return multivector(T, c) end, function(c) return multivector(T, c) end)
  ga.PS = `[multivector(T, kvectors[N])]{array([T](1))}
  ga.invPS = `[multivector(T, kvectors[N])]{array([T](1))}
  
  return ga
end

return macro(GA, GA)
