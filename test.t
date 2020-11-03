-- TTest: Standard test library for Terra.

local oldenv = getfenv()
local TT = {}
for k,v in pairs(oldenv) do
  TT[k] = v
end

package.terrapath = package.terrapath .. ';../?.t'
local FS = require 'std.fs'
local O = require 'std.object'
local ffi = require 'ffi'
local Time = require 'std.time'
local Math = require 'std.math'
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
TT.ROOT_DIR = ""

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
      if type(err.err) == "cdata" then
        err.err = ffi.string(err.err)
      end
      if type(err.source) == "cdata" then
        err.source = ffi.string(err.source)
      end
      print("[" .. err.source .. ":" .. err.line .. "] " .. err.err)
    else -- If it's a real error (not an assert) then propagate
      TT.errored = TT.errored + 1
      error(err)
    end
  end
  TT.stack[#TT.stack] = nil
end

-- For temporarily disabling tests
function TT.xdescribe(text, f) end
function TT.xit(text, f) end

local function Assertion(b, s, src, l)
  if not b then
    local e = {source = src, line = l}
    if s == nil then
      e.err = "assertion failed!"
    else
      e.err = s
    end
    error(e)
  end
end

-- This allows us to call the assertion from terra and produce an error that we can catch without blowing up the macro
local runassert_t = terralib.cast({bool, rawstring, rawstring, int} -> {}, Assertion)

setmetatable(TT.assert, {
  __call = function(self, b, s, offset)
    offset = offset or 0
    Assertion(b, s, debug.getinfo(2 + offset).short_src, debug.getinfo(2 + offset).currentline)
  end
})

local function assertTerra(v, desc)
  -- 8 is the current stack depth when terra evaluates macros. Hopefully it doesn't change! ᕕ( ᐛ )ᕗ
  local src = debug.getinfo(8).short_src
  local line = debug.getinfo(8).currentline
  return `runassert_t([v], [desc], [src], [line])
end

local function getTypeString(t)
  if terralib.isquote(t) then
    return tostring(t:gettype())
  end
  return type(t)
end

function TT.assert.is_true(v)
  local desc = "Expected boolean true value, but got (" .. getTypeString(v) .. ") " .. tostring(v)
  if terralib.isquote(v) then
    if v:gettype() ~= bool then
      return assertTerra(`false, desc, 1)
    end
    return assertTerra(`v == true, desc, 1)
  else 
    TT.assert(type(v) == "boolean" and v == true, desc, 1)
  end
end

function TT.assert.is_false(v)
  local desc = "Expected boolean false value, but got (" .. getTypeString(v) .. ") " .. tostring(v)
  if terralib.isquote(v) then
    if v:gettype() ~= bool then
      return assertTerra(`false, desc, 1)
    end
    return assertTerra(`v == false, desc, 1)
  else 
    TT.assert(type(v) == "boolean" and v == false, desc, 1)
  end
end

function TT.assert.truthy(v)
  local desc = "Expected truthy value.\nPassed in: (" .. getTypeString(v) .. ")\n" .. tostring(v)
  if terralib.isquote(v) then
    return assertTerra(`[bool](v) == true, desc, 1)
  else
    TT.assert(v ~= false and v ~= nil, desc, 1)
  end
end

function TT.assert.falsy(v)
  local desc = "Expected falsy value.\nPassed in: (" .. getTypeString(v) .. ")\n" .. tostring(v)
  if terralib.isquote(v) then
    return assertTerra(`[bool](v) == false, desc, 1)
  else
    TT.assert(not (v ~= false and v ~= nil), desc, 1)
  end
end

-- Basic deep comparison, can't handle cycles
function deepCompare(l, r)
  if type(l) ~= "table" or type(r) ~= "table" then
    return l == r
  end
  if rawequal(l, r) then
    return true
  end

  for k,v in next, l do
    if not deepCompare(v, r[k]) then
      return false
    end
  end
  for k,v in next, r do
    if l[k] == nil then return false end
  end

  return true
end

function terraCompare(l, r, noteq)
  if not terralib.isquote(l) or not terralib.isquote(r) then
    return `[noteq]
  end
  local lt = l:gettype()
  local rt = r:gettype()
  if (lt.convertible == "tuple" and rt.convertible == "tuple") or (lt == rt and lt:isstruct()) then
    local self_entries = lt:getentries()
    local acc = `true
    for i, ent in ipairs(self_entries) do
      local result = terraCompare(`l.[self_entries[i].field], `r.[self_entries[i].field], noteq)
      if noteq then
        acc = `[acc] or [result]
      else
        acc = `[acc] and [result]
      end
    end
    return acc
  end
  if lt:ispointer() and rt == niltype then
    rt = lt
  end
  if lt == niltype and rt:ispointer() then
    lt = rt
  end
  
  if lt ~= rt and (not lt:isarithmetic() or not rt:isarithmetic()) then
    return `[noteq]
  end
  if lt:isarray() then
    local acc = `true
    for i=0,lt.N-1 do
      if noteq then
        acc = `[acc] or [l][ [i] ] ~= [r][ [i] ]
      else
        acc = `[acc] and [l][ [i] ] == [r][ [i] ]
      end
    end
    return acc
  end

  if noteq then
    return `[l] ~= [r]
  end
  return `[l] == [r]
end

-- trim6 from http://lua-users.org/wiki/StringTrim
local function trim(s)
   return s:match'^()%s*$' and '' or s:match'^%s*(.*%S)'
end

function TT.assert.equal(l, ...)
  for i,v in ipairs({...}) do
    local desc = 
      "Expected objects to be equal.\nPassed in: (" .. getTypeString(v) .. ")\n" .. 
      trim(tostring(v)) .. 
      "\nExpected: (" .. getTypeString(l) .. ")\n" .. 
      trim(tostring(l))

    if terralib.isquote(v) then
      return assertTerra(terraCompare(l, v, false), desc)
    else
      TT.assert(deepCompare(l, v), desc, 1)
    end
  end
end

function TT.assert.fail(f, expected)
  local ok, err_actual = pcall(f)
  TT.assert(not ok, "Expected an error but didn't get one!", 1)
  if not ok and expected ~= nil then
    TT.assert(deepCompare(expected, err_actual), " Expected error:\n" .. tostring(expected) .. "\nFound:\n" .. tostring(err_actual), 1)
  end
end

function TT.assert.success(f)
  local ok, err_actual = pcall(f)
  if not ok then
    TT.assert(ok, "Did not expect an error, but got: " .. err_actual, 1)
  end
end

function TT.assert.unique(...)
  for i,v in ipairs({...}) do
    for i2, v2 in pairs({...}) do
      if i ~= i2 and type(v) == type(v2) then
        local desc = tostring(i) .. " and " .. tostring(i2) .. " should be unique, but both are (" .. getTypeString(v) .. ") " .. tostring(v)
        if terralib.isquote(v) then
          return assertTerra(terraCompare(v, v2, true), desc)
        else
          TT.assert(not deepCompare(v, v2), desc, 1)
        end
      end
    end
  end
end

function TT.assert.near(l, r, epsilon)
  if not epsilon then
    epsilon = 0.000001
  end
    local desc = 
      "Expected objects to be nearly equal.\nPassed in: (" .. getTypeString(r) .. ")\n" .. 
      trim(tostring(r)) .. 
      "\nExpected: (" .. getTypeString(l) .. ")\n" .. 
      trim(tostring(l))

  if terralib.isquote(r) then
    return assertTerra(`Math.abs(r - l) < [l:gettype()]([epsilon]), desc)
  else
    TT.assert(math.abs(l - r) < epsilon, desc, 1)
  end
end

function TT.assert.unreachable() TT.assert(false, "Should never reach this point!", 1) end

TT.assert.is_true = macro(TT.assert.is_true, TT.assert.is_true)
TT.assert.is_false = macro(TT.assert.is_false, TT.assert.is_false)
TT.assert.truthy = macro(TT.assert.truthy, TT.assert.truthy)
TT.assert.falsy = macro(TT.assert.falsy, TT.assert.falsy)
TT.assert.equal = macro(TT.assert.equal, TT.assert.equal)
TT.assert.fail = macro(TT.assert.fail, TT.assert.fail)
TT.assert.success = macro(TT.assert.success, TT.assert.success)
TT.assert.unique = macro(TT.assert.unique, TT.assert.unique)
TT.assert.near = macro(TT.assert.near, TT.assert.near)

local DefaultConfig = {
  default = {
    ROOT = {"."},
    lpath = "",
    tpath = "",
  }
}

local function RunTest(path, folder)
  local res, err = terralib.loadfile(ffi.string(path))
  if not res then print(err) end
  TT.stack = {}
  TT.ROOT_DIR = ffi.string(folder)
  setfenv(res, TT)
  res, err = xpcall(res, function(err)
        print(err)
        print(debug.traceback())
      end)
  if not res then print(err) end
end

local runtest_t = terralib.cast({rawstring, rawstring} -> {}, RunTest)

terra CallTest(folder : rawstring, root : rawstring) : rawstring
  var s = O.new(FS.path, folder) / root
  
  for i in FS.dir(s) do
    if i.folder then
      CallTest(s, i.filename)
    else
      var file = s / i.filename
      if C.strcmp(file:extension(), "t") == 0 then
        runtest_t(file, s.s)
      end
    end
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
runtest_t:free()
runassert_t:free()

local diff = Time.Clock() - TT.start
print((TT.total - TT.failed - TT.errored) .. " successes / " .. TT.failed .. " failures / " .. TT.errored .. " errors : " .. string.format("%3.3f seconds", diff))
