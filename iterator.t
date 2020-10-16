local CT = require 'std.constraint'

local M = {}

M.Iterator = CT.TerraOperator("__for")
M.Iteratable = CT.Method("iter", {}, CT.Value(M.Iterator))

M.FromSlice = terralib.memoize(function(T)
  local struct s {
    f : &T
    l : &T
  }

  s.metamethods.__for = function(iter,body)
      return quote
          var p = iter.f
          while p ~= iter.l do
              [body(`@p)]
              p = p + 1
          end
      end
  end

  return s
end)

return M