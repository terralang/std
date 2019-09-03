local Object = require 'std.object'.Object

describe('object', function()
    it('should provide a deinit method on a struct', function()
        local struct foo(Object) {
            a: int
            b: int
        }

        local terra bar()
            var f = [foo]{1, 2}
            var s = f.a + f.b
            f:deinit()
            return s
        end

        assert.equal(bar(), 3)
    end)

    it('should provide _init positional initialization', function()
        local struct foo(Object) {
            a: int
            b: int
        }

        terra foo:init(a: int, b: int)
            self:_init {a, b}
        end

        local terra bar()
            var f: foo
            f:init(1, 2)
            var s = f.a + f.b
            f:deinit()
            return s
        end

        assert.equal(bar(), 3)
    end)

    it('should provide _init named initialization', function()
        local struct foo(Object) {
            a: int
            b: int
        }

        terra foo:init(a: int, b: int)
            self:_init {a = a, b = a + b}
        end

        local terra bar()
            var f: foo
            f:init(1, 2)
            var s = f.a + f.b
            f:deinit()
            return s
        end

        assert.equal(bar(), 5)
    end)

    it('should allow nesting init tuples in _init named initialization', function()
        local struct foo(Object) {
            a: int
            b: int
        }

        terra foo:init(a: int, b: int)
            self:_init {a = a, b = a + b}
        end

        local struct bar(Object) {
            c: foo
            d: int
        }

        terra bar:init(a: int, b: int, c: int)
            self:_init {c = {a, b}, d = c}
        end

        local terra baz()
            var b: bar
            b:init(1, 2, 3)

            var s = b.c.a + b.c.b + b.d
            b:deinit()
            return s
        end

        assert.equal(baz(), 8)
    end)
end)