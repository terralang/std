local Iterator = require 'std.iterator'
local O = require 'std.object'
local Alloc = require 'std.alloc'
local ffi = require 'ffi'
local C = nil
if ffi.os == "Windows" then
C = terralib.includecstring [[
#include <string.h>
#include <stdio.h>

#pragma pack(push)
#pragma pack(8)
#define WINVER        0x0601 //_WIN32_WINNT_WIN7
#define _WIN32_WINNT  0x0601
#define NTDDI_VERSION 0x06010000 // NTDDI_WIN7
#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX // Some compilers enable this by default
  #define NOMINMAX
#endif
#define NOBITMAP
#define NOMCX
#define NOSERVICE
#define NOHELP
#include <windows.h>
#pragma pack(pop)

LONGLONG ToUnixTimestamp(FILETIME ft)
{
  LARGE_INTEGER date, diff;
  date.HighPart = ft.dwHighDateTime;
  date.LowPart = ft.dwLowDateTime;

  // Diff between 1970 and 1607 converted to 100-nanoseconds
  diff.QuadPart = 11644473600000 * 10000;

  return (date.QuadPart - diff.QuadPart) / 10000000; // convert to seconds and return
}

]]
else
C = terralib.includecstring [[
#include <sys/types.h>  // stat().
#include <sys/stat.h>   // stat().
#include <dirent.h>
#include <unistd.h> // rmdir()

#include <stdio.h>
]]
end

local F = {}

local replaceChar = terralib.overloadedfunction("replaceChar",
{ terra(s : rawstring, from : int8, to : int8) : {}
    while @s ~= 0 do
      if @s == from then
        @s = to
      end
      s = s + 1
    end
  end,
  terra(s : &uint16, from : uint16, to : uint16) : {}
    while @s ~= 0 do
      if @s == from then
        @s = to
      end
      s = s + 1
    end
  end})

local terra normalize(p : rawstring) : rawstring
  if p == nil then
    return nil
  end

  var len = C.strlen(p) + 1
  var s = Alloc.alloc(int8, len)
  Alloc.copy(s, p, len)

  replaceChar(s, ('\\')[0], ('/')[0])
  if s[len - 1] == ('/')[0] then
    s[len - 1] = 0
  end

  return s
end

struct F.path(O.Object) {
  s : rawstring
}

F.path.methods.init = terralib.overloadedfunction("init", {
  terra(self : &F.path) : {}
    self.s = nil
  end,
  terra(self : &F.path, p : rawstring) : {}
    self.s = normalize(p)
  end
})

terra F.path:normalize() : {}
  self.s = normalize(self.s)
end

terra F.path:destruct() : {}
  if self.s ~= nil then
    Alloc.free(self.s)
  end
end

local terra path_concat(l : rawstring, r : rawstring, extra : int) : rawstring
  replaceChar(r, ('\\')[0], ('/')[0])
  var first = C.strlen(l)
  var len = first + C.strlen(r) + 1
  var s = Alloc.alloc(int8, len + extra)
  Alloc.copy(s, l, first)

  if first == 0 or l[first-1] == ('/')[0] then
    extra = 0
  end

  if extra > 0 then
    s[first] = ('/')[0]
  end

  Alloc.copy(s + first + extra, r, len - first)
  return s
end

local terra absolute_path(s : rawstring) : bool
  var pos = C.strchr(s, ('/')[0])
  return pos ~= nil and ((pos == s) or (pos[-1] == (':')[0]))
end

terra F.path:concat(p : rawstring) : {}
  if self.s ~= nil then
    var s = path_concat(self.s, p, 0)
    Alloc.free(self.s)
    self.s = s
  else
    self.s = normalize(p)
  end
end

terra F.path:append(p : rawstring) : {}
  if self.s ~= nil then
    var s = path_concat(self.s, p, 1)
    Alloc.free(self.s)
    self.s = s
  else
    self.s = normalize(p)
  end
end

terra F.path:is_relative() return not absolute_path(self.s) end
terra F.path:is_absolute() return absolute_path(self.s) end

terra F.path:filename() : rawstring
  var pos = C.strrchr(self.s, ('/')[0])
  return terralib.select(pos ~= nil, pos + 1, self.s)
end

F.path.methods.parent = O.destroy(terra(self : &F.path) : F.path
  var pos = C.strrchr(self.s, ('/')[0])
  if pos == nil then
    return F.path{nil}
  end
  var last = @pos
  @pos = 0
  var p = normalize(pos)
  @pos = last
  return F.path{p}
end)

terra F.path:extension() : rawstring
  var pos = self:filename()
  pos = C.strrchr(self.s, ('.')[0])
  return terralib.select(pos ~= nil, pos + 1, self.s)
end

terra F.path:remove_extension() : {}
  var pos = self:filename()
  pos = C.strrchr(self.s, ('.')[0])
  if pos ~= nil then
    @pos = 0
  end
end

F.path.metamethods.__cast = function(from, to, exp)
  if from == rawstring and to == F.path then
    return `F.path{normalize(exp)}
  end
  if from == niltype and to == F.path then
    return `F.path{nil}
  end
  if from == F.path and to == rawstring then
    return `exp.s
  end
  error(("unknown conversion %s to %s"):format(tostring(from),tostring(to)))
end

--F.path.metamethods.__add = macro(function(a, b)
--  local ta = a:gettype()
--  local tb = b:gettype() 
--end)

struct F.Info {
  exists : bool
  folder : bool
  symlink : bool
  size : uint64
  lastwrite : uint64
  lastaccess : uint64
  filename : rawstring -- only populated during folder iteration
}

if ffi.os == "Windows" then
  local CP_UTF8 = constant(65001)
  local INVALID_FILE_ATTRIBUTES = constant(C.DWORD, `-1LL)
  local FILE_ATTRIBUTE_DIRECTORY = constant(C.DWORD, 0x00000010)
  local FILE_ATTRIBUTE_REPARSE_POINT = constant(C.DWORD, 0x00000400)
  local INVALID_HANDLE_VALUE = constant(&opaque, `[&opaque](-1LL))
  local DOT_DIR = `arrayof([uint16], ('.')[0], 0)
  local DOTDOT_DIR = `arrayof([uint16], ('.')[0], ('.')[0], 0)

  local terra towchar(p : rawstring, extra : uint, skip : uint) : &uint16
    var len = C.MultiByteToWideChar(CP_UTF8, 0, p, -1, nil, 0)
    var out = Alloc.alloc(uint16, len + extra) + skip
    C.MultiByteToWideChar(CP_UTF8, 0, p, -1, out, len);
    return out
  end

  local terra fromwchar(p : &uint16) : rawstring
    var len = C.WideCharToMultiByte(CP_UTF8, 0, p, -1, nil, 0, nil, nil)
    var out = Alloc.alloc(int8, len)
    C.WideCharToMultiByte(CP_UTF8, 0, p, -1, out, len, nil, nil);
    return out
  end

  local windowfy = macro(function(p)
    return quote
      var v = towchar(p, 0, 0)
      replaceChar(v, ('\\')[0], ('/')[0])
      defer Alloc.free(v)
    in
      v
    end
  end)

  local terra translatefileinfo(pdata : &C._WIN32_FILE_ATTRIBUTE_DATA) : F.Info
    var size : C._LARGE_INTEGER
    return F.Info{pdata.dwFileAttributes ~= INVALID_FILE_ATTRIBUTES, 
      (pdata.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) ~= 0,
      (pdata.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT) ~= 0,
      ([uint64](pdata.nFileSizeHigh) << 32) or pdata.nFileSizeLow,
      C.ToUnixTimestamp(pdata.ftLastWriteTime),
      C.ToUnixTimestamp(pdata.ftLastAccessTime),
      nil }
  end

  terra F.attributes(p : rawstring) : F.Info
    var s = windowfy(p)
    var attr : C._WIN32_FILE_ATTRIBUTE_DATA
    
    if C.GetFileAttributesExW(s, 0, &attr) ~= 0 then
      return translatefileinfo(&attr)
    end
    return F.Info{false}
  end

  terra F.chdir(p : rawstring) : bool
    return C.SetCurrentDirectoryW(windowfy(p)) ~= 0
  end

  F.currentdir = O.destroy(terra() : F.path
    var len = C.GetCurrentDirectoryW(0, nil)
    var out = Alloc.alloc(uint16, len)
    C.GetCurrentDirectoryW(len, out)
    defer Alloc.free(out)
    return F.path{fromwchar(out)}
  end)

  terra F.mkdir(p : rawstring) : bool
    var s = windowfy(p)

    var pos = C.wcschr(s, ('\\')[0]);
    while pos ~= nil do
      var last = @pos
      @pos = 0
      if C.GetFileAttributesW(s) == INVALID_FILE_ATTRIBUTES and C.CreateDirectoryW(s, nil)==0 then
        return false
      end
      @pos = last
      pos = C.wcschr(pos + 1, ('\\')[0]);
    end

    if C.GetFileAttributesW(s) == INVALID_FILE_ATTRIBUTES and C.CreateDirectoryW(s, nil)==0 then
      return false
    end

    var attr = C.GetFileAttributesW(s)
    return terralib.select(attr == INVALID_FILE_ATTRIBUTES, false, (attr and FILE_ATTRIBUTE_DIRECTORY) ~= 0)
  end
  
  struct F.Directory {
    handle : &opaque
    ffd : C._WIN32_FIND_DATAW
  }

  local function FolderIterW(iter,body)
    local terra freehandle(handle : &opaque) : {}
      if handle ~= nil and handle ~= INVALID_HANDLE_VALUE then
        C.FindClose(handle)
      end
    end
    
    return quote
      var p : F.Directory = iter
      defer freehandle(p.handle) -- in case the loop terminates early
      while p.handle ~= nil and p.handle ~= INVALID_HANDLE_VALUE do
        if C.wcscmp(p.ffd.cFileName, DOT_DIR) ~= 0 and C.wcscmp(p.ffd.cFileName, DOTDOT_DIR) ~= 0 then
          [body(`p)]
        end
        if C.FindNextFileW(p.handle, &p.ffd) <= 0 then
          C.FindClose(p.handle)
          p.handle = nil
        end
      end
    end
  end

  F.Directory.metamethods.__for = function(iter,body)
    return FolderIterW(iter, function(p)
        return quote
          var i = translatefileinfo([&C._WIN32_FILE_ATTRIBUTE_DATA](&p.ffd))
          i.filename = fromwchar(p.ffd.cFileName)
          defer Alloc.free(i.filename)
          [body(`i)]
        end
      end)
  end

  terra F.dir(p : rawstring) : F.Directory
    var s = towchar(p, 1, 0)
    defer Alloc.free(s)
    replaceChar(s, ('\\')[0], ('/')[0])
    var len = C.wcslen(s)
    s[len] = ('*')[0]
    s[len + 1] = 0
    var d : F.Directory
    d.handle = C.FindFirstFileW(s, &d.ffd)
    return d
  end

  local terra rmdirloop(s : &uint16, i : F.Directory) : bool
    var slen = C.wcslen(s)
    var flen = C.wcslen(i.ffd.cFileName)
    var f = Alloc.alloc(uint16, flen + slen + 2)
    Alloc.copy(f, [&uint16](i.ffd.cFileName), flen)
    if s[slen - 1] ~= ('/')[0] then
      f[flen] = ('/')[0]
      flen = flen + 1
    end
    Alloc.copy(f + flen, s, slen)
    defer Alloc.free(f)
    
    if (i.ffd.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) ~= 0 then
      var d : F.Directory
      d.handle = C.FindFirstFileW(f, &d.ffd)
      [FolderIterW(d, function(x) return `rmdirloop(s, x) end)]
    else
      if C._wremove(f) ~= 0 then
        return false
      end
    end
  end

  terra F.rmdir(p : rawstring) : bool
    var s = towchar(p, 1, 0)
    defer Alloc.free(s)
    replaceChar(s, ('\\')[0], ('/')[0])
    var len = C.wcslen(s)
    s[len] = ('*')[0]
    s[len + 1] = 0
    var d : F.Directory
    d.handle = C.FindFirstFileW(s, &d.ffd)
    
    [FolderIterW(d, function(i) return `rmdirloop(s, i) end)]

    return C.RemoveDirectoryW(s) ~= 0
  end

  terra F.exists(p : rawstring, folder : bool) : bool
    var s = towchar(p, 4, 4)
    defer Alloc.free(s)
    replaceChar(s, ('\\')[0], ('/')[0])

    var pos = C.wcschr(s, ('/')[0])
     
    if pos ~= nil and ((pos == s) or (pos[-1] == (':')[0])) then -- add "\\?\" insane windows nonsense
      s = s - 4
      s[0] = ('\\')[0]
      s[1] = ('\\')[0]
      s[2] = ('?')[0]
      s[3] = ('\\')[0]
    end

    var attr = C.GetFileAttributesW(s)

    if attr == INVALID_FILE_ATTRIBUTES then
      return false
    end

    attr = (attr and FILE_ATTRIBUTE_DIRECTORY)
    return terralib.select(folder, attr ~= 0, attr == 0)
  end
else

end

return F