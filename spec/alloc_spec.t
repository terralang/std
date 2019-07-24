local alloc = require 'alloc'

describe("allocator", function()
           it("should allocate and free memory successfully", function()
                local terra test()
                  var buff = alloc.alloc(uint8, 16)
                  alloc.free(buff)
                  return true
                end

                assert.truthy(test())
           end)


end)
