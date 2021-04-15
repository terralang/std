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

M.Tuple = function(self,body)
    return quote
        escape
            for i=0,#self:gettype().entries - 1 do
              emit(body(`self.["_"..i]))
            end
        end
    end
  end
  
do
    local function iter(invar, state)
        if state < invar[2] then
            return state + 1, invar[1][state+1]
        else
            return nil, nil
        end
    end

    function M.FromArgs(...)
        return iter, {{...}, select("#", ...)}, 0
    end
end

return M