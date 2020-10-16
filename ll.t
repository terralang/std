local CT = require 'std.constraint'
local Iterator = require 'std.iterator'
local L = {}

local function Insert(node, target, nextsym, prevsym, root)
  return quote
    var n = node -- actually copy the pointer
    node.[prevsym] = target.[prevsym]
    node.[nextsym] = target
    if target.[prevsym] ~= nil then
      target.[prevsym].[nextsym] = node
    else
      escape if root then emit(quote @root=node end) end end
    end
    target.[prevsym] = node
  end
end

local function Prepend(node, root, nextsym, prevsym, last)
  return quote
    var n = node -- actually copy the pointer
    n.[prevsym] = nil
    n.[nextsym] = @root
    if (@root) ~= nil then
      (@root).[prevsym] = n
    else 
      escape if last then emit(quote @last=n end) end end
    end
    @root = n
  end
end

local function Append(node, last, nextsym, prevsym, root)
  return quote
    var n = node -- actually copy the pointer
    n.[nextsym] = nil
    n.[prevsym] = @last
    if (@last) ~= nil then
      (@last).[nextsym] = n
    else 
      escape if root then emit(quote @root=n end) end end
    end
    @last = n
  end
end

local function Remove(node, nextsym, prevsym, root, last)
  return quote
    var n = node -- actually copy the pointer
    if n.[prevsym] ~= nil then 
      n.[prevsym].[nextsym] = n.[nextsym]
    else
      escape if root then emit(quote if (@root) == n then @root = n.[nextsym] end end) end end
    end
    if n.[nextsym] ~= nil then 
      n.[nextsym].[prevsym] = n.[prevsym]
    else
      escape if last then emit(quote if (@last) == n then @last = n.[prevsym] end end) end end
    end
  end
end

L.InsertCustom = function(next, prev)
  return CT(function(a) return CT.Meta({CT.Pointer(a), CT.Pointer(a), CT.Optional(CT.Pointer(CT.Pointer(a)))}, tuple(),
    function(node, target, root) return Insert(node, target, next, prev, root) end
  ) end, CT.TerraType)
end

L.PrependCustom = function(next, prev)
  return CT(function(a) return CT.Meta({CT.Pointer(a), CT.Pointer(CT.Pointer(a)), CT.Optional(CT.Pointer(CT.Pointer(a)))}, tuple(),
    function(node, root, last) return Prepend(node, root, next, prev, last) end
  ) end, CT.TerraType)
end

L.AppendCustom = function(next, prev)
  return CT(function(a) return CT.Meta({CT.Pointer(a), CT.Pointer(CT.Pointer(a)), CT.Optional(CT.Pointer(CT.Pointer(a)))}, tuple(),
    function(node, last, root) return Append(node, last, next, prev, root) end
  ) end, CT.TerraType)
end

L.RemoveCustom = function(next, prev)
  return CT(function(a) return CT.Meta({CT.Pointer(a), CT.Optional(CT.Pointer(CT.Pointer(a))), CT.Optional(CT.Pointer(CT.Pointer(a)))}, tuple(),
    function(node, root, last) return Remove(node, next, prev, root, last) end
  ) end, CT.TerraType)
end

-- Inserts node before target and re-assigns root if it's provided
L.Insert = CT(function(a) return CT.Meta({CT.Pointer(a), CT.Pointer(a), CT.Optional(CT.Pointer(CT.Pointer(a)))}, tuple(),
  function(node, target, root) return Insert(node, target, "next", "prev", root) end
) end, CT.TerraType)

-- Inserts node before the root (which must always exist) and re-assigns last if it's provided
L.Prepend = CT(function(a) return CT.Meta({CT.Pointer(a), CT.Pointer(CT.Pointer(a)), CT.Optional(CT.Pointer(CT.Pointer(a)))}, tuple(),
  function(node, root, last) return Prepend(node, root, "next", "prev", last) end
) end, CT.TerraType)

-- Inserts node after the last node (which must always exist) and re-assigns root if it's provided
L.Append = CT(function(a) return CT.Meta({CT.Pointer(a), CT.Pointer(CT.Pointer(a)), CT.Optional(CT.Pointer(CT.Pointer(a)))}, tuple(),
  function(node, last, root) return Append(node, last, "next", "prev", root) end
) end, CT.TerraType)

-- Removes a node from a list and re-assigns root or last if they are provided.
L.Remove = CT(function(a) return CT.Meta({CT.Pointer(a), CT.Optional(CT.Pointer(CT.Pointer(a))), CT.Optional(CT.Pointer(CT.Pointer(a)))}, tuple(),
  function(node, root, last) return Remove(node, "next", "prev", root, last) end
) end, CT.TerraType)

L.MakeIterator = terralib.memoize(function(node, nextsym)
  nextsym = nextsym or "next"
  local struct s {
    cur : &node
  }

  s.metamethods.__for = function(iter,body)
      return quote
          var cur = iter.cur
          while cur ~= nil do
              var tmp = cur.[nextsym]
              [body(cur)]
              cur = tmp
          end
      end
  end

  return s
end)

return L