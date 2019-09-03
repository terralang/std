local ondemand = require 'std.meta.ondemand'

describe('ondemand', function()
    it('should allow calling a lazy function', function()
        local initialized = false
        local foo = ondemand(function()
            initialized = true
            return terra()
                return 4
            end
        end)
        assert.is_false(initialized)
        assert.equal(4, foo())
        assert.is_true(initialized)
    end)

    it('should allow calling a lazy function from terra', function()
        local initialized = false
        local foo = ondemand(function()
            initialized = true
            return terra()
                return 4
            end
        end)
        assert.is_false(initialized)
        local terra bar()
            return foo()
        end
        assert.is_true(initialized)
        assert.equal(bar(), 4)
    end)

    it('should allow calling a lazy function from terra with arguments', function()
        local initialized = false
        local foo = ondemand(function()
            initialized = true
            return terra(a: int)
                return 4 + a
            end
        end)
        assert.is_false(initialized)
        local terra bar(a: int)
            return foo(a)
        end
        assert.is_true(initialized)
        assert.equal(bar(4), 8)
    end)
end)