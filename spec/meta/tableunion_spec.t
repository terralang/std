local tableunion = require 'std.meta.tableunion'

describe('tableunion',function()
  it('should result in the union between two tables', function()
    tableunion({},{}, function(k) assert.unreachable() end)
    tableunion({x=1},{}, function(k) assert.equal("x", k) end)
    tableunion({},{x=1}, function(k) assert.equal("x", k) end)
    local results = {}
    tableunion({x=1},{y=2}, function(k) results[k] = true end)
    assert.equal(results, {x=true,y=true})
    tableunion({x=1},{x=2}, function(k) assert.equal("x", k) end)
    
    results = {}
    tableunion({x=1},{x=2, y=2}, function(k) results[k] = true end)
    assert.equal(results, {x=true,y=true})
    
    results = {}
    tableunion({x=1, y=2},{x=2}, function(k) results[k] = true end)
    assert.equal(results, {x=true,y=true})
  end)
end)