local cond = require 'std.cond'

local M = {}

--LLVM knows how to optimize this. simple implementation, and rely on the optimizer.
terra M.default_copy_raw(dest: &opaque, src: &opaque, len: intptr)
  var dest_int8 = [&int8](dest)
  var src_int8 = [&int8](src)
  for offset = 0,len do
    dest_int8[offset] = src_int8[offset]
  end
end

--LLVM knows how to optimize this. simple implementation, and rely on the optimizer.
M.default_clear_raw = terralib.overloadedfunction( "defaultClearRaw", {
    terra (ptr: &opaque, len: intptr)
      var ptr_ = [&uint8](ptr)
      for offset = 0,len do
        ptr_[offset] = 0
      end
    end,
    terra (ptr: &opaque, len: intptr, val: uint8)
      var ptr_ = [&uint8](ptr)
      for offset = 0,len do
        ptr_[offset] = val
      end
    end
  }
)

function M.wrap_func_as_macro_method(func)
  return macro(function(self, ...)
    local args = {...}
    return `func([...])
  end)
end

-- libC allocator is the default allocator. It uses libc functions to perfrom memory manipulations.

local malloc = terralib.externfunction("malloc", {intptr} -> {&opaque})
local free = terralib.externfunction("free", {&opaque} -> {})
local calloc = terralib.externfunction("calloc", {intptr, intptr} -> {&opaque})
local realloc = terralib.externfunction("realloc", {&opaque, intptr} -> {&opaque})
local memcpy = terralib.externfunction("memcpy", {&opaque, &opaque, intptr} -> {})


struct M.libc_allocator {}

terra M.libc_allocator:alloc_raw(size: intptr): &opaque
  return malloc(size)
end

terra M.libc_allocator:free_raw(ptr: &opaque): {}
  free(ptr)
end

terra M.libc_allocator:calloc_raw(size: intptr, nelems: intptr): &opaque
  return calloc(size, nelems)
end

terra M.libc_allocator:realloc_raw(ptr: &opaque, old_size: intptr, new_size: intptr): &opaque
  return realloc(ptr, new_size)
end

terra M.libc_allocator:copy_raw(dest: &opaque, src: &opaque, size: intptr)
  memcpy(dest, src, size)
end


-- Populate the methods of an allocator
-- Some methods can have working defaults.
-- Some high level APIs can be derived from low level APIs
-- By composing all of these derivations, allocators can be made easily from a minimal set of functionality.
function M.populate_allocator_methods(allocator)
  if not allocator:getmethod 'alloc_raw' then
    error "allocator doesn't have alloc_raw defined and no default behavior is available"
  end
  if not allocator:getmethod 'alloc' then
    allocator.methods.alloc = macro(function(self, T, len)
      if not len then len = 1 end
      local type = T:astype()
      return `[&type](self:alloc_raw([terralib.sizeof(type)]*len))
    end)
  end

  if not allocator:getmethod 'free_raw' then
    error "allocator doesn't have free_raw defined and no default behavior is available"
  end
  if not allocator:getmethod 'free' then
    allocator.methods.free = macro(function(self, ptr)
      return quote
        self:free_raw([&opaque](ptr))
      end
    end)
  end

  if not allocator:getmethod 'clear_raw' then
    allocator.methods.clear_raw = macro(function(self, ptr, len, val)
      if not val then
        return `M.defaultClearRaw(ptr, len)
      else
        return `M.defaultClearRaw(ptr, len, val)
      end
    end)
  end
  if not allocator:getmethod 'clear' then
    allocator.methods.clear = macro(function(self, ptr, len, val)
      local type = ptr:gettype().type --base type of pointer
      if val then
        return `self:clear_raw([&opaque](ptr), len*[terralib.sizeof(type)], val)
      else
        return `self:clear_raw([&opaque](ptr), len*[terralib.sizeof(type)])
      end
    end)
  end

  if not allocator:getmethod 'calloc_raw' then
    terra allocator:calloc_raw(size: intptr, nelems: intptr)
      var regionsize = size * nelems
      var region = self:alloc_raw(regionsize)
      self:clear_raw(region, regionsize)
      return region
    end
  end
  if not allocator:getmethod 'calloc' then
    allocator.methods.calloc = macro(function (self, T, nelems)
      local type = T:astype()
      return `self:calloc_raw([terralib.sizeof(type)], nelems)
    end)
  end

  if not allocator:getmethod 'copy_raw' then
    allocator.methods.copy_raw = macro(function(self, dest, src, len)
      return `M.default_copy_raw(dest, src, len)
    end)
  end
  if not allocator:getmethod 'copy' then
    allocator.methods.copy = macro(function(self, dest, src, len)
      if dest:gettype() ~= src:gettype() then
        error "source and destination pointers of a copy are of different types. allocator copying cannot handle type casting or conversion."
      end
      return `self:copy_raw([&opaque](dest), [&opaque](src), len*[terralib.sizeof(dest:gettype().type)])
    end)
  end

  if not allocator:getmethod 'realloc_raw' then
    allocator.methods.realloc_raw = macro(function(self, ptr, old_size, new_size)
      return quote
        var self_ = self
        var new_size_ = new_size
        var old_size_ = old_size
        var new_ptr = self_:alloc(new_size_)
        self_:copy_raw(new_ptr, ptr, cond(new_size_ < old_size_, new_size_, old_size_))
      in
        new_ptr
      end
    end)
  end
  if not allocator:getmethod 'realloc' then
    allocator.methods.realloc = macro(function(self, ptr, old_size, new_size)
      local type = ptr:gettype().type
      return `self:realloc_raw([&opaque](ptr), old_size * [terralib.sizeof(type)], new_size * [terralib.sizeof(type)])
    end)
  end

  if not allocator:getmethod 'new' then
    allocator.methods.new = macro(function(self, T, ...)
      local args = {...}
      local type = T:astype()
      return quote
        var res = self:alloc(T)
        res:init([args])
      in
        res
      end
    end)
  end

  if not allocator:getmethod 'delete' then
    allocator.methods.delete = macro(function(self, ptr)
      return quote
        var ptr_ = ptr
        ptr_:destroy()
        self:free(ptr_)
      end
    end)
  end
end


M.populate_allocator_methods(M.libc_allocator)

M.default_allocator = global(M.libc_allocator)

M.alloc = macro(function(T, len) return `M.default_allocator:alloc(T, len) end)
M.free = macro(function(ptr) return `M.default_allocator:free(ptr) end)
M.clear = macro(function(ptr, len, val) return `M.default_allocator:clear(ptr, len, val) end)
M.calloc = macro(function(T, len) return `M.default_allocator:calloc(T, len) end)
M.realloc = macro(function(ptr, len) return `M.default_allocator:realloc(ptr, len) end)
M.copy = macro(function(dest, src, len) return `M.default_allocator:copy(dest, src, len) end)
M.new = macro(function(T) return `M.default_allocator:new(T) end)
M.delete = macro(function(ptr) return `M.default_allocator:delete(ptr) end)

return M
