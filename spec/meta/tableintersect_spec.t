local tableintersect = require 'std.meta.tableintersect'

describe('tableintersect',function()
  it('should result in an intersection between two tables', function()
    tableintersect({},{}, function(k) assert.unreachable() end)
    tableintersect({1},{}, function(k) assert.unreachable() end)
    tableintersect({},{1}, function(k) assert.unreachable() end)
    tableintersect({x=1},{y=2}, function(k) assert.unreachable() end)
    tableintersect({x=1},{x=2}, function(k) assert.equal("x", k) end)
    tableintersect({x=1},{x=2, y=2}, function(k) assert.equal("x", k) end)
    tableintersect({x=1, y=2},{x=2}, function(k) assert.equal("x", k) end)
  end)
end)