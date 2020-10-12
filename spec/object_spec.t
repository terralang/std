local O = require 'std.object'

describe('object', function()
    it('should provide a destruct method on a struct', function()
        local struct foo(O.Object) {
            a: int
            b: int
        }

        local terra bar()
            var f = [foo]{1, 2}
            var s = f.a + f.b
            f:destruct()
            return s
        end

        assert.equal(bar(), 3)
    end)

    it('should provide _init positional initialization', function()
        local struct foo(O.Object) {
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
            f:destruct()
            return s
        end

        assert.equal(bar(), 3)
    end)

    it('should provide _init named initialization', function()
        local struct foo(O.Object) {
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
            f:destruct()
            return s
        end

        assert.equal(bar(), 4)
    end)

    it('should allow nesting init tuples in _init named initialization', function()
        local struct foo(O.Object) {
            a: int
            b: int
        }

        terra foo:init(a: int, b: int)
            self:_init {a = a, b = a + b}
        end

        local struct bar(O.Object) {
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
            b:destruct()
            return s
        end

        assert.equal(baz(), 7)
    end)

    it('should defer destructors correctly', function()
        local struct Tracker(O.Object) {
            constructed : bool
            destructed : int
        }
        terra Tracker:init()
            self.constructed = true
            self.destructed = 0
        end
        terra Tracker:destruct()
            self.destructed = self.destructed + 1
        end

        terra foo() : Tracker
            return O.new(Tracker)
        end

        local wrapped = O.destroy(terra() : Tracker
            return Tracker {true, 0}
        end)

        terra foobar() : Tracker
            var x = wrapped()
            assert.is_true(x.constructed)
            assert.equal(x.destructed, 0)
            return x -- This can't be tested, because the copy happens before the deferred destruction
        end

        terra check()
            var v = foo()
            assert.is_true(v.constructed)
            assert.equal(v.destructed, 1)
            foobar()
            var m = Tracker{false, 0}
            assert.is_false(m.constructed)
            assert.equal(m.destructed, 0)
            do
                O.new(m)
                assert.is_true(m.constructed)
                assert.equal(m.destructed, 0)
            end
            assert.is_true(m.constructed)
            assert.equal(m.destructed, 1)
        end

        check()
    end)
end)