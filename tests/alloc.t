local alloc = require 'alloc'

local terra test()
  var buff = alloc.alloc(uint8, 16)
  alloc.free(buff)
  return true
end


assert(test(), "failed to allocate and free memory")
