

describe("enum", function()
           import "std.enum"

           it("should be able to create enums without value types", function()
                local enum foo {
                  a, b
                         }
           end)

           it("should be able to create enums with specified types", function()
                local enum foo {
                  get: tuple(int),
                  set: tuple(int, int)
                               }
           end)

           it("should be able to distinguish values of an enum", function()
                local enum foo { a, b }

                local terra bar(x: bool) : bool
                  var f: foo
                  if x then
                    f = foo.a{}
                  else
                    f = foo.b{}
                  end

                  return f:is_a()
                end

                assert.is_true(bar(true))
                assert.is_false(bar(false))
           end)

           it("should be able to retrieve values from an alternative", function()
                local enum op {
                  get: tuple(int),
                  set: tuple(int, int)
                              }
                local enum res {
                  none, some: tuple(int)
                               }

                local struct store {
                  vals: int[5]
                                   }

                terra store:operate(o: op): res
                  if o:is_get() then
                    return res.some{self.vals[o.get._0]}
                  end
                  if o:is_set() then
                    self.vals[o.set._0] = o.set._1
                    return res.none{}
                  end
                end

                local s = terralib.new(store)
                local r

                r = s:operate(op.methods.set{0, 0})
                assert.is_true(r:is_none())
                assert.is_false(r:is_some())

                r = s:operate(op.methods.set{1, 1})
                assert.is_true(r:is_none())

                r = s:operate(op.methods.get{0})
                assert.is_true(r:is_some())
                assert.equal(0, r.some._0)

                r = s:operate(op.methods.get{1})
                assert.is_true(r:is_some())
                assert.equal(1, r.some._0)
           end)
end)
