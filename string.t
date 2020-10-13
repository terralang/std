local Iterator = require 'std.iterator'
local O = require 'std.object'
local Alloc = require 'std.alloc'
local ffi = require 'ffi'
local C = nil

if ffi.os == "Windows" then
C = terralib.includecstring [[
#include <string.h>
#include <ctype.h>
#include <stdio.h> // for vsnprintf

char* STRTOK(char* str, char const* delim, char** context) {
  return strtok_s(str, delim, context);
}
]]
else
C = terralib.includecstring [[
#include <string.h>
#include <ctype.h>
#include <stdio.h>

char* STRTOK(char* str, char const* delim, char** context) {
  return strtok_r(str, delim, context);
}
]]

end
local terra allocString(p : rawstring, len : uint)
  if p == nil then
    return nil
  end

  if len == 0 then
    len = C.strlen(p)
  end

  var s = Alloc.alloc(int8, len + 1)
  Alloc.copy(s, p, len)
  s[len] = 0
  return s
end

struct String(O.Object) {
  s : rawstring
}

String.methods.init = terralib.overloadedfunction("init", {
  terra(self : &String) : {}
    self.s = nil
  end,
  terra(self : &String, p : rawstring) : {}
    self.s = allocString(p, 0)
  end,
  terra(self : &String, p : rawstring, n : uint) : {}
    self.s = allocString(p, n)
  end
})

terra String:destruct() : {}
  if self.s ~= nil then
    --C.printf("FREED: %s\n", self.s)
    Alloc.free(self.s)
  end
end

-- Strings are mostly immutable, but we do allow you to replace individual characters because this won't invalidate the destructor
terra String:replace(old : int8, new : int8)
  var cur = self.s

  while cur ~= nil do 
    cur = C.strchr(self.s, old)
    if cur ~= nil then
      @cur = new
      cur = cur + 1
    end
  end
end

local terra concat(s : rawstring, p : rawstring) : String
  if s == nil then
    return String { allocString(p, 0) }
  end
  if p == nil then
    return String { allocString(s, 0) }
  end
  var n : rawstring
  var len1 = C.strlen(s)
  var len2 = C.strlen(p)
  n = Alloc.alloc(int8, len1 + len2 + 1)
  Alloc.copy(n, s, len1)
  Alloc.copy(n + len1, p, len2)
  n[len1 + len2] = 0
  return String { n }
end

String.methods.Concat = O.destroy(concat)
String.methods.append = O.destroy(terra(self : &String, p : rawstring) return concat(self.s, p) end)

String.metamethods.__cast = function(from, to, exp)
  if (from == String or from == &String) and to == rawstring then
    return `exp.s
  end
  error(("unknown conversion %s to %s"):format(tostring(from),tostring(to)))
end

String.metamethods.__add = macro(function(a, b)
  if type(a) == "string" or a:gettype() == rawstring then
    return `String.Concat(a, b.s)
  elseif type(b) == "string" or b:gettype() == rawstring then
    return `String.Concat(a.s, b)
  end
  return `String.Concat(a.s, b.s)
end)

terra String.metamethods.__eq(a : rawstring, b : rawstring)
  if a == nil and b == nil then return true end
  if a == nil or b == nil then return false end
  return C.strcmp(a, b) == 0
end

terra String.metamethods.__ne(a : rawstring, b : rawstring)
  return not [String.metamethods.__eq](a, b)
end

terra String.metamethods.__le(a : rawstring, b : rawstring)
  if a == nil and b == nil then return true end
  if a == nil or b == nil then return false end
  return C.strcmp(a, b) <= 0
end

terra String.metamethods.__ge(a : rawstring, b : rawstring)
  if a == nil and b == nil then return true end
  if a == nil or b == nil then return false end
  return C.strcmp(a, b) >= 0
end

terra String.metamethods.__lt(a : rawstring, b : rawstring)
  return not [String.metamethods.__ge](a, b)
end

terra String.metamethods.__gt(a : rawstring, b : rawstring)
  return not [String.metamethods.__le](a, b)
end

String.methods.sub = O.destroy(terra(self : &String, start : int, length : int) : String
  var l = C.strlen(self.s)
  if start >= l then
    return String{nil}
  end

  l = l - start
  if length > l then
    length = l
  end

  return String{allocString(self.s + start, length)}
end)

local struct TokenIter {
  s : rawstring
  context : rawstring
  delim : int8[8]
}

TokenIter.metamethods.__for = function(iter,body)
  return quote
    var s = C.STRTOK(iter.s, iter.delim, &iter.context)

    while s ~= nil do
      [body(`s)]
      s = C.STRTOK(nil, iter.delim, &iter.context)
    end
  end
end

terra String:tokens(delim : rawstring) : TokenIter
  var iter = TokenIter{ self.s, nil }
  C.strncpy(iter.delim, delim, 8)
  iter.delim[7] = 0
  return iter
end

terra String:find(c : int8) : rawstring
  return C.strchr(self.s, c)
end

terra String:findlast(c : int8) : rawstring
  return C.strrchr(self.s, c)
end

terra String:iter() : Iterator.FromSlice(int8)
  return [Iterator.FromSlice(int8)]{self.s, self.s + C.strlen(self.s)}
end

String.methods.tolower = O.destroy(terra(self : &String) : String
  var s = allocString(self.s, 0)

  for i=0,C.strlen(self.s) do
    s[i] = C.tolower(self.s[i])
  end

  return String{s}
end)

String.methods.toupper = O.destroy(terra(self : &String) : String
  var s = allocString(self.s, 0)

  for i=0,C.strlen(self.s) do
    s[i] = C.toupper(self.s[i])
  end

  return String{s}
end)

local va_start = terralib.intrinsic("llvm.va_start", {&int8} -> {})
local va_end = terralib.intrinsic("llvm.va_end", {&int8} -> {})

String.methods.Format = O.destroy(terra(format : rawstring, ...) : String
  var vl : C.va_list
  va_start([&int8](&vl))
  var len = C.vsnprintf(nil, 0, format, vl);
  va_end([&int8](&vl))
  
  if len < 0 then return String{nil} end

  var s = Alloc.alloc(int8, len + 1)
  var vl2 : C.va_list -- vsnprintf will have modified vl so we need a new one
  va_start([&int8](&vl2))
  C.vsnprintf(s, len + 1, format, vl2);
  va_end([&int8](&vl2))

  return String{s}
end)

return String