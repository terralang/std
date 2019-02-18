local cond = require 'cond'


local terra simpletest(c: bool, a: int, b: int)
    return cond(c, a, b)
end

assert(simpletest(true, 1, 2) == 1, "selecting the first value works")
assert(simpletest(false, 1, 2) == 2, "selecting the second value works")

local terra variadictest(val: int)
    return cond(
        val == 1, 2,
        val == 2, 1,
        val == 3, 5,
        val == 4, 4,
        val == 5, 3,
        0
    )
end

local results = {2, 1, 5, 4, 3, 0, 0}

for i, v in ipairs(results) do
    assert(variadictest(i) == v, "variadic test matches expectation of "..tostring(i).." => "..tostring(v))
end

local terra lazytest()
    var a = 0
    var b = cond(false, [quote a = a + 1 in a end], 0)
    return a + b
end

assert(lazytest() == 0, "cond lazily evaluates the subexpressions.")
