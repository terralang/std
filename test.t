-- TTest: Standard test library for Terra.

local oldenv = getfenv()
local TT = {}
for k,v in pairs(oldenv) do
  TT[k] = v
end

package.terrapath = package.terrapath .. '../?.t'
local FS = require 'std.fs'
local O = require 'std.object'
local ffi = require 'ffi'
local Time = require 'std.time'
local C = terralib.includecstring [[
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <malloc.h>

#if !(defined(WIN32) || defined(_WIN32) || defined(_WIN64) || defined(__TOS_WFG__) || defined(__WINDOWS__))
#include <alloca.h>
#endif

// Windows defines alloca to _alloca but terra can't process defines.
void *fg_alloca(size_t size) { return alloca(size); }

]]

TT.stack = {}
TT.failed = 0
TT.total = 0
TT.errored = 0
TT.start = Time.Clock()
TT.assert = {}

function TT.describe(text, f)
  table.insert(TT.stack, #TT.stack + 1, text)
  f()
  TT.stack[#TT.stack] = nil
end

function TT.it(text, f)
  TT.assert(#TT.stack > 0, "it() must be called inside describe()")
  table.insert(TT.stack, #TT.stack + 1, text)
  TT.total = TT.total + 1
  local ok, err = pcall(f)
  if not ok then
    -- Check for a "fake" error and catch it.
    if type(err) == "table" and err.source then
      TT.failed = TT.failed + 1
      local line = ""
      for i,v in ipairs(TT.stack) do
        if i == 1 then
          line = v
        else
          line = line .. " " .. v
        end
      end
      print(line)
      print("[" .. err.source .. ":" .. err.line .. "] " .. err.err)
    else -- If it's a real error (not an assert) then propagate
      TT.errored = TT.errored + 1
      error(err)
    end
  end
  TT.stack[#TT.stack] = nil
end

setmetatable(TT.assert, {
  __call = function(self, b, s)
    if not b then
      local e = {source = debug.getinfo(1).short_src, line = debug.getinfo(1).currentline}
      if s == nil then
        e.err = "assertion failed!"
      else
        e.err = s
      end
      error(e)
    end
  end
})

function getTypeString(t)
  if type(t) == "table" and terralib.isquote(t) then
    return tostring(t:gettype())
  end
  return type(t)
end

function TT.assert.truthy(...)
  for i,v in ipairs({...}) do
    TT.assert(v ~= false and v ~= nil, "Expected truthy value.\nPassed in: (" .. getTypeString(v) .. ")\n" .. tostring(v))
  end
end

function TT.assert.falsy(...)
  for i,v in ipairs({...}) do
    TT.assert(not (v ~= false and v ~= nil), "Expected falsy value.\nPassed in: (" .. getTypeString(v) .. ")\n" .. tostring(v))
  end
end

function TT.assert.equal(l, ...)
  for i,v in ipairs({...}) do
    TT.assert(l == v, 
      "Expected objects to be equal.\nPassed in: (" .. getTypeString(v) .. ")\n" .. 
      tostring(v) .. 
      "\nExpected: (" .. getTypeString(l) .. ")\n" .. 
      tostring(l))
  end
end

function TT.assert.error(f, expected)
  local ok, err_actual = pcall(f)
  TT.assert(not ok, "Expected an error but didn't get one!")
  if not ok and expected ~= nil then
    TT.assert(l == v, " Expected error:\n" .. expected .. "\nFound:\n" .. err_actual)
  end
end

function TT.assert.success(f)
  local ok, err_actual = pcall(f)
  TT.assert(ok, "Did not expect an error, but got: " .. err_actual)
end

function TT.assert.unique(...)
  for i,v in ipairs({...}) do
    for i2, v2 in pairs({...}) do
      if i ~= i2 then
        TT.assert(v ~= v2, tostring(i) .. " and " .. tostring(i2) .. " should be unique, but both are (" .. getTypeString(v) .. ") " .. tostring(v))
      end
    end
  end
end

TT.assert.truthy = macro(TT.assert.truthy, TT.assert.truthy)
TT.assert.falsy = macro(TT.assert.falsy, TT.assert.falsy)
TT.assert.same = macro(TT.assert.same, TT.assert.same)
TT.assert.equal = macro(TT.assert.equal, TT.assert.equal)
TT.assert.error = macro(TT.assert.error, TT.assert.error)
TT.assert.success = macro(TT.assert.success, TT.assert.success)
TT.assert.unique = macro(TT.assert.unique, TT.assert.unique)

local DefaultConfig = {
  default = {
    ROOT = {"."},
    lpath = "",
    tpath = "",
  }
}

local function RunTest(path)
  local res, err = terralib.loadfile(ffi.string(path))
  if not res then print(err) end
  TT.stack = {}
  setfenv(res, TT)
  res, err = xpcall(res, function(err)
        print(err)
        print(debug.traceback())
      end)
  if not res then print(err) end
end

local runtest_t = terralib.cast(rawstring -> {}, RunTest)

terra CallTest(folder : rawstring, root : rawstring) : rawstring
  var s : FS.path
  O.construct(s)
  s:append(folder)
  s:append(root)

  var path : FS.path
  O.construct(path)
  path:append(s)
  path:append("*.t")

  for i in FS.dir(path) do    
    var file : FS.path
    O.construct(file)
    file:append(s)
    file:append(i.filename)
    runtest_t(file)
  end
end

function ProcessConfig(folder, config)
  local tpath = package.terrapath
  local lpath = package.path
  package.terrapath = package.terrapath .. ";" .. config.tpath
  package.path = package.path .. ";" .. config.lpath

  for i,v in ipairs(config.ROOT) do
    CallTest(folder, v)
  end

  package.path = lpath
  package.terrapath = tpath
end

function ProcessFolder(folder, groups)
  if string.sub(folder, -1, -1) ~= "/" then 
    folder = folder .. "/"
  end

  local file, err = loadfile(folder .. ".ttest")
  if not file then
    error(err)
    return
  end

  local configs = file()
  local all = DefaultConfig
  
  if configs["_all"] ~= nil then
    for k,v in pairs(configs["_all"]) do all[k] = v end
  end

  -- For each group we're testing, assemble the full configuration object for it
  for i,v in ipairs(groups) do
    if configs[v] ~= nil then
      local config = {}
      for k,v in pairs(all) do config[k] = v end
      for k,v in pairs(configs[v]) do config[k] = v end
      ProcessConfig(folder, config)
    end
  end
end

function ProcessArgs(args)
  local folders = {}
  local groups = {}

  for i,v in ipairs(args) do
    local a = FS.attributes(v)
    if not a.exists then
      table.insert(groups, v)
    elseif a.folder then
      table.insert(folders, v)
    end
  end

  if #groups == 0 then
    table.insert(groups, "default")
  end
  if #folders == 0 then
    table.insert(folders, ".")
  end

  for i,v in ipairs(folders) do
    ProcessFolder(v, groups)
  end
end

ProcessArgs(arg)

local diff = Time.Clock() - TT.start
print((TT.total - TT.failed - TT.errored) .. " successes / " .. TT.failed .. " failures / " .. TT.errored .. " errors : " .. string.format("%3.3f seconds", diff))