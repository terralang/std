local genstore = require 'std.meta.genstore'

describe('genstore',function()
           local foo = macro(function(a, b) return genstore{a = a, b = b} end)

           it('should allow creating constants', function()
                local terra bar()
                  return foo(1, 2)
                end
                assert.equal(terralib.sizeof(bar.type.returntype), 0) -- type of store is a unit type with no storage.
           end)

           it('should allow creating runtime data', function()
                local terra bar(a: int, b: int)
                  return foo(a, b)
                end
                assert.equal(terralib.sizeof(bar.type.returntype), 2* terralib.sizeof(int))
           end)

           it('should allow creating mixed data', function()
                local terra bar(a: int)
                  return foo(a, 4)
                end
                assert.equal(terralib.sizeof(bar.type.returntype), 1* terralib.sizeof(int))
           end)

           it('should allow naming the generated types', function()
                assert.equal(genstore({}, "footype"):gettype().name, "footype")
           end)

           it('should allow defining methods on generated types', function()
                assert.equal(genstore({}, function(store)
                                 terra store:baz()
                                   return 1
                                 end
                                          end
                                     ):gettype().methods.baz.type.returntype,
                             int)
           end)
end)
