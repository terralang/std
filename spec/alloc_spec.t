local alloc = require 'std.alloc'
local Object = require 'std.object'.Object

describe("allocator", function()
           it("should allocate and free memory successfully", function()
                local terra test()
                  var buff = alloc.alloc(uint8, 16)
                  alloc.free(buff)
                  return true
                end

                assert.truthy(test())
           end)

           it("should call constructors and destructors successfully", function()
              local struct foo(Object) {
                  a: int
                  b: int
              }

              local terra test()
                var buff = alloc.new(foo, 1, 2)
                var res = buff.a + buff.b
                alloc.delete(buff)
                return res
              end

              assert.equal(test(), 3)
           end)
end)
