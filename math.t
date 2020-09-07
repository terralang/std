local M = {}
local template = require 'std.template'

M.min = template(function(T, U)
  local terra min(x:T, y:U) return terralib.select(x < y, x, y) end
  return min
end)

M.max = template(function(T, U)
  local terra max(x:T, y:U) return terralib.select(x > y, x, y) end
  return max
end)

M.abs = template(function(T)
  if T == float then return terra(x:float) return [terralib.intrinsic("llvm.fabs.f32", float -> float)](x) end end
  if T == double then return terra(x:double) return [terralib.intrinsic("llvm.fabs.f64", double -> double)](x) end end
  local terra abs(x:T) return terralib.select(x < 0, -x, x) end
  return abs
end)

for _, name in pairs{"sqrt", "sin", "cos", "log", "log2", "log10", "exp", "exp2", "exp10", "fabs", "ceil", "floor", "trunc", "rint", "nearbyint", "round"} do
  local f = terralib.overloadedfunction(name)
  for tname, ttype in pairs{f32 = float, f64 = double} do
    local d = terra(x: ttype) return [terralib.intrinsic("llvm."..name.."."..tname, ttype -> ttype)](x) end
    f:adddefinition(d)
    M[name.."_"..tname:sub(2)] = d
  end
  M[name] = f
end

M.pow_f32 = terra(x:float, y:float) : float return [terralib.intrinsic("llvm.pow.f32", {float, float} -> float)](x,y) end
M.pow_f64 = terra(x:double, y:double) : double return [terralib.intrinsic("llvm.pow.f64", {double, double} -> double)](x,y) end
M.powi_f32 = terra(x:float, y:int) : float return [terralib.intrinsic("llvm.powi.f32", {float, int} -> float)](x,y) end
M.powi_f64 = terra(x:double, y:int) : double return [terralib.intrinsic("llvm.powi.f64", {double, int} -> double)](x,y) end
M.pow = terralib.overloadedfunction("pow", {M.pow_f32, M.pow_f64, M.powi_f32, M.powi_f64})

return M
