local Iterator = require 'std.iterator'
local O = require 'std.object'
local Alloc = require 'std.alloc'
local ffi = require 'ffi'

local C = nil
local C2 = nil
local F = {}

if ffi.os == "Windows" then
C = terralib.includecstring [[
#include <string.h>
#include <stdio.h> // for _wremove

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
C, C2 = terralib.includecstring [[
#include <sys/types.h>  // stat().
#include <sys/stat.h>   // stat().
#include <dirent.h>
#include <unistd.h> // rmdir()
#include <ftw.h>
#include <string.h>
#include <stdio.h> // for remove()

char _T_ISDIR(m) { return S_ISDIR(m); }
time_t get_atime(struct stat* st) { return st->st_atime; }
time_t get_mtime(struct stat* st) { return st->st_mtime; }

int _deldir_func(const char *fpath, const struct stat *sb, int typeflag)
{
  if(typeflag==FTW_D)
    return rmdir(fpath);
  if(typeflag==FTW_F)
    return unlink(fpath);
  return remove(fpath);
}
]]
end

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

terra F.path:destruct() : {}
  if self.s ~= nil then
    Alloc.free(self.s)
  end
end

local terra path_concat(l : rawstring, r : rawstring, extra : int) : rawstring
  while r[0] == ('/')[0] or r[0] == ('\\')[0] do r = r + 1 end

  var first = C.strlen(l)
  var second = C.strlen(r)

  while r[second - 1] == ('/')[0] or r[second - 1] == ('\\')[0] do 
    second = second - 1
  end

  var len = first + second + 1
  var s = Alloc.alloc(int8, len + extra)
  Alloc.copy(s, l, first)

  if first == 0 or l[first-1] == ('/')[0] or l[first-1] == ('\\')[0] then
    extra = 0
  end

  if extra > 0 then
    s[first] = ('/')[0]
  end

  Alloc.copy(s + first + extra, r, second)
  s[len + extra - 1] = 0
  replaceChar(s, ('\\')[0], ('/')[0])
  return s
end

local terra absolute_path(s : rawstring) : bool
  var pos = C.strchr(s, ('/')[0])
  return pos ~= nil and ((pos == s) or (pos[-1] == (':')[0]))
end

F.path.methods.concat = O.destroy(terra(self : &F.path, p : rawstring) : F.path
  if self.s ~= nil then
    return F.path{path_concat(self.s, p, 0)}
  else
    return F.path{normalize(p)}
  end
end)

F.path.methods.append = O.destroy(terra(self : &F.path, p : rawstring) : F.path
  if self.s ~= nil then
    return F.path{path_concat(self.s, p, 1)}
  else
    return F.path{normalize(p)}
  end
end)

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
  if (from == F.path or from == &F.path) and to == rawstring then
    return `exp.s
  end
  error(("unknown conversion %s to %s"):format(tostring(from),tostring(to)))
end

F.path.metamethods.__add = macro(function(a, b)
  if type(a) == "string" or a:gettype() == rawstring then
    return O.destroy(`F.path{path_concat(a, b.s, 0)})
  elseif type(b) == "string" or b:gettype() == rawstring then
    return O.destroy(`F.path{path_concat(a.s, b, 0)})
  end
  return O.destroy(`F.path{path_concat(a.s, b.s, 0)})
end)

F.path.metamethods.__div = macro(function(a, b)
  if type(a) == "string" or a:gettype() == rawstring then
    return O.destroy(`F.path{path_concat(a, b.s, 1)})
  elseif type(b) == "string" or b:gettype() == rawstring then
    return O.destroy(`F.path{path_concat(a.s, b, 1)})
  end
  return O.destroy(`F.path{path_concat(a.s, b.s, 1)})
end)


terra F.path.metamethods.__eq(a : rawstring, b : rawstring)
  if a == nil and b == nil then return true end
  if a == nil or b == nil then return false end
  return C.strcmp(a, b) == 0
end

terra F.path.metamethods.__ne(a : rawstring, b : rawstring)
  return not [F.path.metamethods.__eq](a, b)
end

terra F.path.metamethods.__le(a : rawstring, b : rawstring)
  if a == nil and b == nil then return true end
  if a == nil or b == nil then return false end
  return C.strcmp(a, b) <= 0
end

terra F.path.metamethods.__ge(a : rawstring, b : rawstring)
  if a == nil and b == nil then return true end
  if a == nil or b == nil then return false end
  return C.strcmp(a, b) >= 0
end

terra F.path.metamethods.__lt(a : rawstring, b : rawstring)
  return not [F.path.metamethods.__ge](a, b)
end

terra F.path.metamethods.__gt(a : rawstring, b : rawstring)
  return not [F.path.metamethods.__le](a, b)
end

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
      replaceChar(v, ('/')[0], ('\\')[0])
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
          [body(i)]
        end
      end)
  end

  terra F.dir(p : rawstring) : F.Directory
    var s = towchar(p, 2, 0)
    defer Alloc.free(s)
    replaceChar(s, ('/')[0], ('\\')[0])
    var len = C.wcslen(s)
    s[len] = ('\\')[0]
    s[len + 1] = ('*')[0]
    s[len + 2] = 0
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

    s[len] = 0
    return C.RemoveDirectoryW(s) ~= 0
  end

  terra F.exists(p : rawstring, folder : bool) : bool
    var s = towchar(p, 4, 4)
    defer Alloc.free(s - 4)
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
  local S_IFDIR = constant(C.mode_t, 0x4000)
  local S_IFLNK = constant(C.mode_t, 0xA000)
  
  local terra translatefileinfo(st : &C2.stat) : F.Info
    return F.Info{true, 
      (st.st_mode and S_IFDIR) == S_IFDIR,
      (st.st_mode and S_IFLNK) == S_IFLNK,
      st.st_size,
      C.get_mtime(st),
      C.get_atime(st),
      nil }
  end
  
  terra F.attributes(p : rawstring) : F.Info
    var st : C2.stat
    if C.stat(p, &st) ~= 0 then
      return F.Info{false}
    end

    return translatefileinfo(&st)
  end

  terra F.chdir(p : rawstring) : bool
    return C.chdir(p) == 0
  end

  F.currentdir = O.destroy(terra() : F.path
    var s = Alloc.alloc(int8, 2048)
    if C.getcwd(s, 2048) == nil then
      Alloc.free(s)
      return F.path{nil}
    end
    return F.path{s}
  end)

  struct F.Directory {
    handle : &C.DIR
  }

  F.Directory.metamethods.__for = function(iter,body)
    local terra freehandle(handle : &C.DIR) : {}
      if handle ~= nil then
        C.closedir(handle)
      end
    end
    
    return quote
      var p = iter.handle
      defer freehandle(p) -- in case the loop terminates early
      
      if p ~= nil then
        var st : C2.stat
        var dent : &C.dirent = C.readdir(p)

        while dent ~= nil do
          if C.strcmp(dent.d_name, ".") ~= 0 and C.strcmp(dent.d_name, "..") ~= 0 and C.fstatat(C.dirfd(p), dent.d_name, &st, 0) == 0 then
            var info = translatefileinfo(&st)
            info.filename = dent.d_name
            [body(`info)]
          end
          
          dent = C.readdir(p)
        end
      end
    end
  end

  terra F.dir(p : rawstring) : F.Directory
    return F.Directory { C.opendir(p) }
  end

  terra F.mkdir(p : rawstring) : bool
    return C.mkdir(p, 0700) == 0
  end

  terra F.rmdir(p : rawstring) : bool
    return C.ftw(p,C._deldir_func, 20) == 0
  end

  terra F.exists(p : rawstring, folder : bool) : bool
    var st : C2.stat
    if C.stat(p, &st) ~= 0 then
      return false
    end
    return (C._T_ISDIR(st.st_mode)^terralib.select(folder, 1, 0)) == 0
  end

end

return F
