local LL = require 'std.ll'
local Alloc = require 'std.alloc'

describe("Linked List", function()
  local struct List {
    next : &List
    prev : &List
  }
  local struct ListMod {
    nextmod : &ListMod
    prevmod : &ListMod
  }

  local terra grab() : &List
    return Alloc.new(List, nil, nil)
  end

  local terra grabmod() : &ListMod
    return Alloc.new(ListMod, nil, nil)
  end

  local function verify_list_t(root, next, prev, ...)
    local args = {...}

    if #args == 0 then
      return quote assert.equal(root, nil) end
    end

    return quote
      var nodes = array([args])
      var cur = root

      escape 
        for i = 1,#args do
          emit(quote 
            assert.unique(cur, nil)
            assert.equal(cur.[prev], terralib.select(i > 1, nodes[i - 2], nil))
            assert.equal(cur.[next], terralib.select(i < [#args], nodes[i], nil))
            cur = cur.[next]
          end)
        end
      end
    end
  end

  local verify_list = macro(function(root, ...) return verify_list_t(root, "next", "prev", ...) end)
  local verify_listmod = macro(function(root, ...) return verify_list_t(root, "nextmod", "prevmod", ...) end)

  it("should operate on a default list correctly", terra()
    var root : &List = nil
    var nodes = array(grab(), grab(), grab(), grab())

    verify_list(root)
    verify_list(nodes[0], nodes[0])

    LL.Prepend(nodes[0], &root)
    verify_list(root, nodes[0])

    LL.Remove(root, &root)
    verify_list(root)

    LL.Prepend(nodes[0], &root)
    verify_list(root, nodes[0])

    LL.Insert(nodes[1], nodes[0], &root)
    verify_list(root, nodes[1], nodes[0])

    LL.Insert(nodes[2], nodes[0], &root)
    verify_list(root, nodes[1], nodes[2], nodes[0])

    LL.Prepend(nodes[3], &root)
    verify_list(root, nodes[3], nodes[1], nodes[2], nodes[0])

    LL.Remove(root, &root)
    verify_list(root, nodes[1], nodes[2], nodes[0])
    
    LL.Insert(nodes[3], nodes[0], &root)
    verify_list(root, nodes[1], nodes[2], nodes[3], nodes[0])

    while root ~= nil do LL.Remove(root, &root) end
    verify_list(root)

    var last : &List = nil

    LL.Prepend(nodes[0], &root, &last)
    verify_list(root, nodes[0])
    assert.equal(last, nodes[0])

    LL.Remove(root, &root, &last)
    verify_list(root)
    assert.equal(last, nil)

    LL.Append(nodes[0], &last, &root)
    verify_list(root, nodes[0])
    assert.equal(last, nodes[0])

    LL.Insert(nodes[1], nodes[0], &root)
    verify_list(root, nodes[1], nodes[0])
    assert.equal(last, nodes[0])

    LL.Insert(nodes[2], nodes[0], &root)
    verify_list(root, nodes[1], nodes[2], nodes[0])
    assert.equal(last, nodes[0])

    LL.Append(nodes[3], &last, &root)
    verify_list(root, nodes[1], nodes[2], nodes[0], nodes[3])
    assert.equal(last, nodes[3])

    LL.Remove(last, &root, &last)
    verify_list(root, nodes[1], nodes[2], nodes[0])
    assert.equal(last, nodes[0])
    
    LL.Insert(nodes[3], nodes[0], &root)
    verify_list(root, nodes[1], nodes[2], nodes[3], nodes[0])
    assert.equal(last, nodes[0])
  end)

  local insert = LL.InsertCustom("nextmod", "prevmod")
  local prepend = LL.PrependCustom("nextmod", "prevmod")
  local append = LL.AppendCustom("nextmod", "prevmod")
  local remove = LL.RemoveCustom("nextmod", "prevmod")

  it("should operate on a custom list correctly", terra()
    var root : &ListMod = nil
    var nodes = array(grabmod(), grabmod(), grabmod(), grabmod())

    verify_listmod(root)
    verify_listmod(nodes[0], nodes[0])

    prepend(nodes[0], &root)
    verify_listmod(root, nodes[0])

    remove(root, &root)
    verify_listmod(root)

    prepend(nodes[0], &root)
    verify_listmod(root, nodes[0])

    insert(nodes[1], nodes[0], &root)
    verify_listmod(root, nodes[1], nodes[0])

    insert(nodes[2], nodes[0], &root)
    verify_listmod(root, nodes[1], nodes[2], nodes[0])

    prepend(nodes[3], &root)
    verify_listmod(root, nodes[3], nodes[1], nodes[2], nodes[0])

    remove(root, &root)
    verify_listmod(root, nodes[1], nodes[2], nodes[0])
    
    insert(nodes[3], nodes[0], &root)
    verify_listmod(root, nodes[1], nodes[2], nodes[3], nodes[0])

    while root ~= nil do remove(root, &root) end
    verify_listmod(root)

    var last : &ListMod = nil

    prepend(nodes[0], &root, &last)
    verify_listmod(root, nodes[0])
    assert.equal(last, nodes[0])

    remove(root, &root, &last)
    verify_listmod(root)
    assert.equal(last, nil)

    append(nodes[0], &last, &root)
    verify_listmod(root, nodes[0])
    assert.equal(last, nodes[0])

    insert(nodes[1], nodes[0], &root)
    verify_listmod(root, nodes[1], nodes[0])
    assert.equal(last, nodes[0])

    insert(nodes[2], nodes[0], &root)
    verify_listmod(root, nodes[1], nodes[2], nodes[0])
    assert.equal(last, nodes[0])

    append(nodes[3], &last, &root)
    verify_listmod(root, nodes[1], nodes[2], nodes[0], nodes[3])
    assert.equal(last, nodes[3])

    remove(last, &root, &last)
    verify_listmod(root, nodes[1], nodes[2], nodes[0])
    assert.equal(last, nodes[0])
    
    insert(nodes[3], nodes[0], &root)
    verify_listmod(root, nodes[1], nodes[2], nodes[3], nodes[0])
    assert.equal(last, nodes[0])
  end)
end)