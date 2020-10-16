local bit = require 'std.bit'

function is_power_of_2(n)
  local k = 1
  for i=1,10 do
    if n == k then return true end
    k = k * 2
  end
  return n == 0
end

function smallest_ge_power_of_2(n)
  if n == 0 then return 0 end

  local k = 1
  for i=1,12 do
    if k >= n then return k end
    k = k * 2
  end

  return k
end

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
                  assert.equal(is_power_of_2(i), test(i))
                end
           end)

           it("should be able to find the smallest ge power of two", function()
                local terra testa(x: int) return bit.smallest_ge_pow2(x) end
                local terra testb(x: int) return bit.smallest_ge_pow2_b(x) end
                for i = 1, 500 do
                  assert.equal(smallest_ge_power_of_2(i), testa(i), testb(i))
                end
           end)
end)
