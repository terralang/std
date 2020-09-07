local bit = require 'std.bit'

describe("bit module",
         function()
           it("should compute count of leading zeros", function()
                local terra test(x: int) return bit.ctlz(x) end
                for i = 1, 10 do
                  assert.equal(32 - i - 1, test(2 ^ i))
                end
           end)

           it("should be able to check if something is a power of two", function()
                local terra test(x: int) return bit.is_pow2(x) end
                for i = 1, 500 do
                  assert.equal(math.log(i, 2) % 1 == 0, test(i))
                end
           end)

           it("should be able to find the smallest ge power of two", function()
                local terra testa(x: int) return bit.smallest_ge_pow2(x) end
                local terra testb(x: int) return bit.smallest_ge_pow2_b(x) end
                for i = 1, 500 do
                  assert.equal(2 ^ math.ceil(math.log(i, 2)), testa(i), testb(i))
                end
           end)
end)
