local M = {}
local template = require 'std.template'

M.ctlz = template(function(T, defzero)
    if not T:isintegralorvector() then
      error "attempted to count leading zeroes of something that is neither an integer or a vector of integers."
    end
    local typecode = ""
    local basetype = T
    if T:isvector() then
      basetype = T.type
      typecode = "v"..tostring(T.N)
    end
    typecode = typecode .. (basetype.signed and "i" or "u") ..tostring(basetype.bytes * 8)
    local ctlz
    if not defzero then
      terra ctlz(a: T)
        return [terralib.intrinsic("llvm.ctlz."..typecode, {T, bool} -> T)](a, true)
      end
    else
      terra ctlz(a:T, z: defzero)
        return [terralib.intrinsic("llvm.ctlz."..typecode, {T, bool} -> T)](a, z)
      end
    end
    return ctlz
end)

M.is_pow2 = template(function(T)
    local terra is_pow2(x: T)
      return (x and (x - 1)) == 0
    end
    return is_pow2
end)

M.smallest_ge_pow2 = template(function(T)
    local terra smallest_ge_pow2(x: T)
      if M.is_pow2(x) then
        return x
      else
        return 1 << ([
                       8 * terralib.sizeof(T:isvector() and T.type or T)
                     ] - M.ctlz(x))
      end
    end
    return smallest_ge_pow2
end)

M.smallest_ge_pow2_b = template(function(T)
    local terra smallest_ge_pow2_b(x: T)
      if M.is_pow2(x) then
        return x
      else
        var v = escape
          local acc = `x-1
          for i = 0, math.log( (T:isvector() and terralib.sizeof(T.type) or terralib.sizeof(T)) * 8, 2 ) - 1 do
            acc = quote var v = [acc] in (v >> [2 ^ i]) or v end
          end
          emit(acc)
                end
        return v + 1
      end
    end
    return smallest_ge_pow2_b
end)

return M
