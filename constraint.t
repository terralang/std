local M = {}
local IsType = terralib.types.istype
local List = require 'terralist'
local tunpack = table.unpack or unpack

local args
do
    local function iter(invar, state)
        if state < invar[2] then
            return state + 1, invar[1][state+1]
        else
            return nil, nil
        end
    end

    function args(...)
        return iter, {{...}, select("#", ...)}, 0
    end
end

local Tautalogy = function() return {} end

local function PushError(err, errors, context, parent) 
  local e = {unpack(context)}
  if parent ~= nil then
    e[#e + 1] = parent
  end
  e[#e + 1] = err
  errors[#errors + 1] = e
  return errors
end

local function QuoteToString(a)
  if terralib.isquote(a) then
    return "|"..(a:gettype():isunit() and "{untyped terra quote}" or tostring(a:gettype())).."|"
  end
  return tostring(a)
end

-- Returns true if a is a subset of b
local function CheckSubset(a, b, context)
  local objs = a:synthesize()
  if #objs == 0 then -- if synthesize returns no types, it's either an invalid constraint or it simply can't be synthesized
    error "Invalid synthesis"
    return false
  end
  return objs:all(function(e)
    local ok, err = pcall(b.pred, b, e, context)
    return ok
  end)
end

local Constraint_mt = {
  __call = function(self, obj, context)
    if context ~= nil and type(context) ~= "table" then
      error "Invalid context!"
    end
    local ok, err = pcall(self.pred, self, obj, context or {})
    if not ok then
      if type(err) ~= "table" then
        err = PushError(err, {}, context or {}, tostring(self))
      end
      
      if #err == 0 then
        error "unknown error occured"
      end

      local function expand(e, idx)
        local str = ""
        for i, v in ipairs(e) do
          if type(v) == "table" then
            str = str..expand(v, idx + 1)
          else
            str = str..string.rep(" ", (i - 1 + idx) * 2)..v.."\n"
          end
        end
        return str
      end
      local str = ""
      for _, v in ipairs(err) do
        str = str..expand(v, 0)
      end

      error (str)
    end
    return err
  end,
  __add = function(a, b) -- or
    return M.MultiConstraint(false, nil, a, b)
  end,
  __mul = function(a, b) -- and
    return M.MultiConstraint(true, nil, a, b)
  end,
  __tostring = function(self)
    return "Constraint["..(self.name and (type(self.name) == "function" and self:name() or self.name) or tostring(self.pred)).."]"
  end,
  __eq = function(self, b)
    return self.pred == b.pred and self:equal(b)
  end,
  __lt = function(self, b)
    return not self:equal(b) and self:subset(b, {})
  end,
  __le = function(self, b)
    return self:equal(b) or self:subset(b, {})
  end,
}

local function ConstraintName(constraint)
  if getmetatable(constraint) == Constraint_mt then
    if not constraint.name then
      return tostring(constraint.pred)
    end
    return type(constraint.name) == "function" and constraint:name() or constraint.name
  end
  return tostring(constraint)
end

M.Constraint = function(predicate, synthesis, tag)
  return setmetatable({ pred = predicate, name = tag, synthesize = function(self) return synthesis end }, Constraint_mt)
end

local function IsConstraint(obj)
  return getmetatable(obj) == Constraint_mt
end

-- The basic predicate checks to see if the types match
local BasicPredicate = function(self, obj, context)
  if obj ~= self.type then
    if tostring(self.type) == tostring(obj) then
      error ("Expected "..tostring(self.type).." but found different type "..tostring(self.type).." which is not identical! Did you forget to memoize a type?")
    end
    error ("Expected "..tostring(self.type).." but found "..tostring(obj).." instead.")
  end
  return {}
end

-- The cast predicate instead attempts to cast the type - note that this is deliberately seperated from the subset operation.
local CastPredicate = function(self, obj, context)
  if not IsType(obj) then
    error ("Expected cast target to be terra type, but instead found "..tostring(obj))
  end
  local t = self.type
  if IsConstraint(t) then
    t = t:synthesize()
  end
  local val = quote var v : obj in [t]([v]) end
  return {}
end

M.BasicConstraint = function(metatype, cast)
  local t = { type = metatype, pred = cast and CastPredicate or BasicPredicate, name = (metatype == nil) and "nil" or ConstraintName(metatype) }
  if cast and not IsType(t.type) and not IsConstraint(t.type) then
    error (tostring(t.type).." must be a non-nil terra type if cast is true.")
  end

  function t:equal(b)
    return self.type == b.type
  end
  function t:synthesize()
    return List{self.type or tuple()}
  end
  function t:subset(obj, context)
    if obj ~= self.type then
      error (tostring(obj).." does not equal "..tostring(self.type))
    end
    return {}
  end
  return setmetatable(t, Constraint_mt)
end

local ValuePredicate = function(self, obj, context)
  if self.constraint == nil then
    if obj ~= nil then
      error ("Expected nil, but found "..tostring(obj))
    end
    return {}
  end
  if IsType(obj) then
    return error("Expected a terra value, but got terra type "..tostring(obj))
  end
  if type(obj) ~= "table" or obj.gettype == nil then
    return error("Expected a terra value, but got "..tostring(obj))
  end
  return self.constraint(obj:gettype(), context)
end

M.ValueConstraint = function(constraint)
  local t = { constraint = constraint, pred = ValuePredicate, name = "|"..((constraint == nil) and "nil" or ConstraintName(constraint)).."|" }

  if t.constraint ~= nil then
    t.constraint = M.MakeConstraint(constraint)
  end
  function t:equal(b)
    return self.constraint == b.constraint
  end
  function t:synthesize()
    return self.constraint and self.constraint:synthesize():map(function(e) return quote var v : e in v end end) or List{nil}
  end
  function t:subset(obj, context)
    if t.constraint == nil then
      if obj ~= nil then
        error ("expected nil but got "..tostring(obj))
      end
      return {}
    end
    return t.constraint:subset(obj, context)
  end
  return setmetatable(t, Constraint_mt)
end

local TypePredicate = function(self, obj, context)
  if not IsType(obj) then
    error (tostring(obj).." is not a terra type!")
  end
  if self.constraint ~= nil then
    return self.constraint(obj, context)
  end
  return {}
end

M.TypeConstraint = function(constraint)
  local t = { constraint = constraint, pred = TypePredicate, name = ((constraint == nil) and "{}" or ConstraintName(constraint)), subset = CheckSubset }

  if t.constraint ~= nil then
    t.constraint = M.MakeConstraint(constraint)
  end
  function t:equal(b)
    return self.type == b.type
  end
  function t:synthesize()
    return self.constraint and self.constraint:synthesize() or List{tuple()}
  end
  return setmetatable(t, Constraint_mt)
end

local LuaPredicate = function(self, obj, context)
  if self.type == nil then
    if obj == nil then
      error "Expected lua object of any type, but found nil!"
    end
  else
    if type(obj) ~= self.type then
      error ("Expected lua object of type "..self.type.." but found "..type(obj))
    end
  end
end

M.LuaConstraint = function(luatype)
  local t = { type = luatype, pred = LuaPredicate, name = "Lua: "..(luatype or "Any") }
  function t:equal(b)
    return self.type == b.type
  end
  function t:synthesize()
    if self.type == "number" then
      return List{0}
    elseif self.type == "string" then
      return List{""}
    elseif self.type == "function" then
      return List{function() end }
    elseif self.type == "table" then
      return List{ {} }
    elseif self.type == nil then
      return List{0, "", function() end, {}}
    end
    return List()
  end
  function t:subset(obj, context)
    if type(obj) ~= self.type then
      error (type(obj).." does not equal "..self.type)
    end
    return {}
  end
  return setmetatable(t, Constraint_mt)
end

local function MergeStruct(a, b)
  a = a:synthesize()
  b = b:synthesize()
  for k,v in pairs(b.methods) do 
    if a.methods[k] ~= nil and a.methods[k]:gettype() ~= v:gettype() then
      error ("Cannot merge different types "..tostring(a.methods[k]:gettype()).." and "..tostring(v:gettype()))
    end
    a.methods[k] = v
  end

  local fieldmap = {}
  for _,v in ipairs(a.entries) do 
    fieldmap[v.field] = v.type
  end

  for _,v in ipairs(b.entries) do
    if fieldmap[v.field] ~= nil and fieldmap[v.field] ~= v.type then
      error ("Cannot merge different types "..tostring(fieldmap[v.field]).." and "..tostring(v.type))
    end
    fieldmap[v.field] = v.type
    a.entries[#a.entries + 1] = { field = v.field, type = v.type }
  end

  return a
end

local MultiPredicate = function(self, obj, context)
  local errors = List()
  for _, v in ipairs(self.list) do
    local ok, err = pcall(v, obj, context)
    if not ok then
      PushError(err, errors, context, self.op and "CONSTRAINT[ALL]" or "CONSTRAINT[ANY]")
    elseif not self.op then
      return errors
    end
  end
  if #errors > 0 then
    error(errors)
  end
  return errors
end

-- "true" means use 'and', "false" means use 'or'
M.MultiConstraint = function(opt, id, ...)
  local t = { id = id, list = List(), pred = MultiPredicate, op = opt, subset = CheckSubset }
  for i, v in args(...) do 
    if IsConstraint(v) and v.pred == t.pred and v.op == t.op then
      v.list:app(function(e) t.list[#t.list + 1] = e end)
    else
      t.list[#t.list + 1] = v
    end
  end

  if #t.list < 2 then
    error ("MultiConstraint needs multiple constraints to be valid, but it has "..#t.list)
  end

  function t:name()
    if self.id ~= nil then
      return id
    end
    
    return "(" .. self.list:map(function(e) return ConstraintName(e) end):concat(self.op and " and " or " or ") .. ")"
  end

  function t:equal(b)
    if #self.list ~= #b.list or self.op ~= b.op then
      return false
    end
    return self.list:alli(function(i, e) return e == b.list[i] end)
  end
  function t:synthesize()
    local all = self.list:flatmap(function(e) return e:synthesize() end)
    if not self.op then
      return all
    else
      return List{all:fold(struct {}, MergeStruct)}
    end
  end
  return setmetatable(t, Constraint_mt)
end

local PointerPredicate = function(self, obj, context)
  if not IsType(obj) then
    error (tostring(obj).." is not a terra type!")
  end
  for i = 1, self.count do
    if not obj:ispointer() then
      error ("Expected "..self.count.." indirection(s) on "..tostring(obj)..", but only found "..(i - 1).."!")
    end
    obj = obj.type
  end
  return self.constraint(obj, context)
end

local function nested_pointer(n, t)
    for i = 1, n do
        t = terralib.types.pointer(t)
    end
    return t
end

M.PointerConstraint = function(base, indirection)
  indirection = indirection or 1
  local t = { constraint = M.MakeConstraint(base), count = indirection, pred = PointerPredicate, name = string.rep("&", indirection)..ConstraintName(base), subset = CheckSubset }
  function t:equal(b)
    return self.constraint == b.constraint and self.count == b.count
  end
  function t:synthesize()
    return self.constraint:synthesize():map(function(e)
      return nested_pointer(self.count, e)
    end)
  end
  return setmetatable(t, Constraint_mt)
end

local MetafuncCall = function(self, ...)
  local params = {...}

  -- Validate each parameter. If our parameter count exceeds our constraint, immediately fail.
  if select("#", ...) > #self.params and self.vararg == nil then
    error ("Function type signature expects at most "..#self.params.." parameters, but was passed "..select("#", ...)..": ("..table.concat({...}, ",")..")")
  end

  -- Otherwise, if our parameter count is lower than our constraint, we simply pass in nil and let the constraint decide if the parameter is optional.
  for i, v in ipairs(self.params) do -- This only works because we're using ipairs on self.parameters, which does not have holes
    v(params[i], {"Metafunc(... "..QuoteToString(params[i]).." ...) [parameter #"..i.."]"})
  end

  -- If we allow varargs in our constraint and have leftover parameters, verify them all
  if self.vararg ~= nil then
    for i=#self.params + 1,#params do
      self.vararg(params[i], {"Metafunc(... "..QuoteToString(params[i]).."...) [parameter #"..i.."]"})
    end
  end
  
  local r = self.raw(...)
  self.result(r, {"Metafunc(...) -> "..QuoteToString(r)})

  return r
end

local MetafuncClear = function(self)
  -- Clear out any meta-type parameters
  if self.typeparams ~= nil then
    for _, v in ipairs(self.typeparams) do
      v.type = nil
    end
  end
end

local function IsMetafunc(obj)
  return getmetatable(obj) == terralib.macro and obj.raw ~= nil
end

local function ExtractTerraTypes(fn)
  return function(...)
    local params = {}
    for i, v in args(...) do
      if v.tree:is("luaobject") and IsType(v.tree.value) then
        params[i] = v:astype()
      else
        params[i] = v
      end
    end
    return fn(unpack(params))
  end
end

-- This builds a typed lua function using M.Number, M.String and M.Table (or just M.Value) to represent expected raw lua values, and
-- assumes metatype() is used to wrap types that should be passed in as terra types, not terra values of that type. It exposes this
-- type information so that constraints can query it, then appends the original function with constraint checks on the parameters
-- and return values.
function M.Meta(params, results, func, varargs)
  if terralib.isfunction(params) then -- if you pass in just a normal terra function, this creates an accurate metatype wrapper around it.
    func = params
    params = func:gettype().parameters:map(function(e) return M.ValueConstraint(e) end)
    results = M.ValueConstraint(func:gettype().returntype)
    varargs = func:gettype().isvararg and M.Any() or nil
    func = function(...) return func(...) end
  end

  results = results or tuple()
  local f = { params = List{unpack(params)}:map(function(v) return M.MakeValue(v) end), result = M.MakeValue(results), raw = func, vararg = varargs, _internal = false }
  
  -- Transform all parameters into constraints
  for i, v in ipairs(params) do
    f.params[i] = M.MakeValue(v)
  end
  
  function f:Types(...)
    if select("#", ...) > #self.typeparams then
      error ("Tried to set "..select("#", ...).." type parameters, but there are only "..#self.typeparams)
    end

     -- Duplicate the macro and return a new macro that skips the type initialization phase
    local n = { params = self.params, result = self.result, raw = self.raw, vararg = self.vararg, _internal = false, typeparams = self.typeparams }
    for i, v in args(...) do
      if v ~= nil then
        if not IsType(v) then
          error ("Cannot assign "..tostring(v).." to a type parameter because it is not a terra type")
        end
        n.typeparams[i].type = v
      else
        n.typeparams[i].type = nil
      end
    end
    
    n.fromlua = function(...) return MetafuncCall(n, ...) end
    n.fromterra = ExtractTerraTypes(n.fromlua)
    return setmetatable(n, terralib.macro)
  end

  f.fromlua = function(...) MetafuncClear(f) return MetafuncCall(f, ...) end
  f.fromterra = ExtractTerraTypes(f.fromlua)

  return setmetatable(f, terralib.macro)
end

-- This is a shortcut for Meta that simply gathers all types from the parameters and passes it into func(), which must return a terra function.
function M.Template(params, results, func, varargs)
  local genfun = terralib.memoize(func)
  return M.Meta(params, results, function(...) 
    local args = terralib.newlist{...}
    local types = args:map(function(x) return x:gettype() end)
    local resfun = genfun(tunpack(types))
    return `resfun([args])
  end, varargs)
end

-- This is used for creating metafunctions that exist as methods attached to a type, automatically adding the type constraint to the parameters
function M.MetaMethod(obj, params, results, func, varargs)
  if not IsType(obj) then
    error ("obj must be a terra type we can attach this method to! Instead we got "..tostring(obj))
  end
  results = results or tuple()
  local f = { params = List{M.MakeValue(M.PointerConstraint(obj))}, result = M.MakeValue(results), raw = func, vararg = varargs, _internal = false }
  
  -- Transform all parameters into constraints
  for i, v in ipairs(params) do
    f.params[i + 1] = M.MakeValue(v)
  end
  
  f.fromlua = function(s, ...)
    if not s:gettype():ispointer() then s = `&s end
    MetafuncClear(f)
    return MetafuncCall(f, s, ...)
  end
  f.fromterra = ExtractTerraTypes(f.fromlua)
  return setmetatable(f, terralib.macro)
end

-- This is a shortcut for MetaMethod that simply gathers all types from the parameters and passes it into func(), which must return a terra function.
function M.TemplateMethod(obj, params, results, func, varargs)
  local genfun = terralib.memoize(func)
  return M.MetaMethod(obj, params, results, function(...) 
    local args = terralib.newlist{...}
    local types = args:map(function(x) return x:gettype() end)
    local resfun = genfun(tunpack(types))
    return `resfun([args])
  end, varargs)
end

local function FunctionPredicate(self, obj, context, parent)
  if terralib.isoverloadedfunction(obj) then
    local errors = List()
    
    if #obj:getdefinitions() == 0 then
      error(tostring(obj).." has no definitions, and thus cannot satisfy "..tostring(self))
    end

    for _, v in ipairs(obj:getdefinitions()) do
      local ok, err = pcall(FunctionPredicate, self, v, context, parent)
      if ok then
        return err
      end
      PushError(err, errors, context)
    end

    error(errors)
  end
  if terralib.isquote(obj) then
    obj = obj:asvalue()
  end
  if terralib.isfunction(obj) then
    obj = M.Meta(obj)
  end
  if not IsMetafunc(obj) then
    if terralib.ismacro(obj) then
      print("WARNING: Skipping constraint validation for "..tostring(self).." because function is a macro! You should use a properly typed metafunction instead.")
      return {}
    end
    error ("Expected terra function or metafunction but got "..tostring(obj))
  end

  local set = obj.params:map(function(e) return e:synthesize() end)
  local results = obj.result:synthesize()
  local max = set:map(function(e) return #e end):fold(#results, math.max)

  if max < 1 then
    error "invalid synthesis occured"
  end

  for i = 1,max do
    local params = set:map(function(e) return e[((i - 1) % #e) + 1] end)
    local result = results[((i - 1) % #results) + 1]
    if parent ~= nil then
      if #params < 1 or params[1].gettype == nil or not params[1]:gettype():ispointer() or params[1]:gettype().type ~= parent then
        error (self.method.." does not have a self parameter with a type matching &"..tostring(parent).." - Instead, found "..tostring(params[1]))
      end 
      table.remove(params, 1)
    end

    -- Validate each parameter. If our parameter count exceeds our constraint, immediately fail.
    if #params > #self.params and self.vararg == nil then
      error ("Constraint accepts up to "..#self.params.." parameters, but was passed "..#params..": ("..params:map(QuoteToString):concat(",")..")")
    end

    local errors = List()
    -- Otherwise, if our parameter count is lower than our constraint, we simply pass in nil and let the constraint decide if the parameter is optional.
    for i, v in ipairs(self.params) do
      --local ok, err = pcall(CheckSubset, params[i], v, context)
      local ok, err = pcall(v, params[i], context)
      if not ok then
        PushError(err, errors, context)
      end
    end

    -- If we allow varargs in our constraint and have leftover parameters, verify them all
    if self.vararg ~= nil then
      for i=#self.params + 1,#params do
        --local ok, err = pcall(CheckSubset, params[i], self.vararg, context)
        local ok, err = pcall(self.vararg, params[i], context)
        if not ok then
          PushError(err, errors, context)
        end
      end
    end
    
    --local ok, err = pcall(CheckSubset, result, self.result, context)
    local ok, err = pcall(self.result, result, context)
    if not ok then
      PushError(err, errors, context)
    end

    if #errors > 0 then
      error(errors)
    end
  end
    
  return {}
end

local function FunctionConstraintName(params, result, vararg)
  return "{"..params:map(function(e) return ConstraintName(e) end):concat(",").."} -> "..ConstraintName(result)
end

M.FunctionConstraint = function(parameters, results, varargs)
  if IsType(parameters) then
    if terralib.types.functype.ispointertofunction(parameters) then
      parameters = functype.type.parameters
      results = functype.type.returntype
    elseif terralib.types.functype.isfunction(parameters) then
      parameters = functype.parameters
      results = functype.returntype
    end
  end

  results = results or tuple()
  local t = { params = List(), pred = FunctionPredicate, result = M.MakeValue(results), subset = CheckSubset }

  if varargs ~= nil then
    t.vararg = M.MakeValue(varargs)
  end

  for i, v in ipairs(parameters) do
    t.params[i] = M.MakeValue(v)
  end
  
  t.name = "Function: "..FunctionConstraintName(t.params, t.result, t.vararg)

  function t:equal(b)
    if #self.params ~= #b.params then
      return false
    end
    return self.params:alli(function(i, e) return e == b.params[i] end) and self.result == b.result and self.vararg == b.vararg
  end
  function t:synthesize()
    return List{M.Meta(self.params, self.result, function() end, self.vararg)}
  end
  return setmetatable(t, Constraint_mt)
end

local function FieldPredicate(self, obj, context)
  if not IsType(obj) then
    error (tostring(obj).." is not a terra type!")
  end
  if not obj:isstruct() then
    error (tostring(obj).." is not a terra struct, and therefore cannot have methods")
  end
  for _, v in ipairs(obj.entries) do
    if v.field == self.field then
      return self.type(v.type, context)
    end
  end
  error ("Could not find field named "..self.field)
end

M.FieldConstriant = function(name, constraint)
  local t = { field = name, type = M.MakeConstraint(constraint), pred = FieldPredicate, name = "Field["..name.."]: "..ConstraintName(constraint), subset = CheckSubset }
  function t:equal(b)
    return self.field == b.field and self.type == b.type
  end
  function t:synthesize()
    return self.type:synthesize():map(function(e) 
      local s = struct {}
      s.entries[1] = { field = self.field, type = e:gettype() }
      return s
    end)
  end
  return setmetatable(t, Constraint_mt)
end

local MethodPredicate = function(self, obj, context)
  if not IsType(obj) then
    error (tostring(obj).." is not a terra type!")
  end
  if not obj:isstruct() then
    error (tostring(obj).." is not a terra struct, and therefore cannot have methods")
  end
  local func = obj.methods[self.method]
  if func == nil then
    error ("Could not find method named "..self.method.." in "..tostring(obj))
  end
  return FunctionPredicate(self, func, context, (not self.static) and obj or nil) -- Do not use (self.static and nil or obj), because nil evaluates to false and breaks the psuedo-ternary operator
end

M.MethodConstraint = function(name, parameters, results, static, varargs)
  local t = M.FunctionConstraint(parameters, results, varargs)
  t.name = "Method["..name.."]: "..FunctionConstraintName(t.params, t.result, t.vararg)
  t.pred = MethodPredicate
  t.method = name
  t.static = static or false

  local func_equal = t.equal
  local func_synth = t.synthesize
  function t:equal(b)
    return self.method == b.method and func_equal(self, b)
  end
  function t:synthesize()
    return func_synth(self):map(function(e) 
      local s = struct {}
      s.entries[1] = { field = self.method, type = e:gettype() }
      return s
    end)
  end
  return setmetatable(t, Constraint_mt)
end

-- Transforms an object into a constraint. Understands either a terra type, a terra function, a metafunction object, or a raw lua function.
function M.MakeConstraint(obj)
  if obj == nil then return M.Any() end -- nil is treated as accepting any type
  if IsConstraint(obj) then return obj end
  if IsType(obj) then return M.BasicConstraint(obj) end
  if type(obj) == "table" then return M.BasicConstraint(tuple(unpack(obj))) end
  if type(obj) == "function" then return M.Constraint(obj) end -- A raw lua function is treated as a custom predicate
  error (tostring(obj).." isn't a valid type to convert to a constraint!")
  return nil
  --if type(obj) == "table"
end

-- Transforms an object into a value constraint.
function M.MakeValue(obj)
  if obj == nil then return nil end
  if IsConstraint(obj) then
    if obj.pred == MultiPredicate then
      return M.MultiConstraint(obj.op, obj.id, unpack(obj.list:map(function(e) return M.MakeValue(e) end)))
    end
    if obj.pred == ValuePredicate or obj.pred == TypePredicate or obj.pred == LuaPredicate or obj.pred == FunctionPredicate or obj.pred == Tautalogy then
      return obj
    end
    return M.ValueConstraint(obj)
  end
  if IsType(obj) or (type(obj) == "table" and getmetatable(obj) == nil) then return M.ValueConstraint(obj) end
  if type(obj) == "function" then return M.ValueConstraint(M.Constraint(obj)) end -- A raw lua function is treated as a custom predicate
  error (tostring(obj).." isn't a valid type to convert to a constraint!")
  return nil
end

-- You can pass in a struct as a shortcut to defining a set of constraints
function M.Struct(name, fields)
  local constraints = {}
  if IsType(fields) and fields:isstruct() then
    for _, v in ipairs(fields.entries) do
      constraints[#constraints + 1] = M.FieldConstriant(v.field, M.MakeConstraint(v.type))
    end
    for k, v in ipairs(fields.methods) do
      constraints[#constraints + 1] = M.MethodConstriant(k, M.MakeConstraint(v:gettype()))
    end
  end
  return M.MultiConstraint(true, name, unpack(constraints))
end

local function ParameterPredicate(self, obj, context)
  if self.type ~= nil and self.type ~= obj then
    error ("Type parameter violated! Expected all parameters to have type "..tostring(self.type).." but found type "..tostring(obj).." instead!")
  end

  self.type = obj
  return self.constraint(obj, context)
end

M.MetaParameter = function(constraint)
  local t = { type = nil, constraint = M.MakeConstraint(constraint), pred = ParameterPredicate }

  function t:name()
    if self.type ~= nil then
      return "MetaParameter("..tostring(self.type).."): "..ConstraintName(self.constraint)
    end
    return "MetaParameter: "..ConstraintName(self.constraint)
  end
  function t:equal(b)
    return self.constraint == b.constraint
  end
  function t:synthesize()
    return t.type or t.constraint:synthesize()
  end
  function t:subset(b, context)
    return t.constraint:subset(b, context)
  end
  return setmetatable(t, Constraint_mt)
end

local function MetaConstraintPredicate(self, obj, context)
  for _, v in ipairs(self.typeparams) do
    v.type = nil
  end
  return self.constraint(obj, context)
  -- If we were tracking additional constraints on the type parameters, we would check them here
end

-- A metaconstraint wraps a more complex constraint statement by applying type relation constraints inside the generated constraint object
function M.MetaConstraint(fn, ...)
  local t = { typeparams = {}, constraint = nil, pred = MetaConstraintPredicate, name = "MetaConstraint[" }
  function t:equal(b)
    for i, v in ipairs(self.typeparams) do
      if v ~= b.params[i] then
        return false
      end
    end
    return self.constraint == b.constraint
  end
  function t:synthesize()
    return t.constraint:synthesize()
  end
  function t:subset(b, context)
    return t.constraint:subset(b, context)
  end

  for i, v in args(...) do 
    if IsConstraint(v) and v.pred == ParameterPredicate then
      t.typeparams[i] = v
    else 
      t.typeparams[i] = M.MetaParameter(v)
    end

    t.name = t.name .. ConstraintName(t.typeparams[i].constraint) -- skip the "MetaParameter" part of the name
    if i ~= select("#", ...) then
      t.name = t.name .. ", "
    end
  end
  t.constraint = fn(unpack(t.typeparams))
  t.name = t.name .. "]: " .. ConstraintName(t.constraint)

  return setmetatable(t, Constraint_mt)
end

local function NegativeMethodPredicate(self, obj, context)
  if IsType(obj) and obj:isstruct() then
    local func = obj.methods[self.member]
    if func ~= nil then
      error ("Found "..self.member..", but it shouldn't exist in "..tostring(obj))
    end
  end
  return {}
end

local function NegativeFieldPredicate(self, obj, context)
  if IsType(obj) and obj:isstruct() then
    for _, v in ipairs(obj.entries) do
      if v.field == self.member then
        error ("Found "..self.member..", but it shouldn't exist in "..tostring(obj))
      end
    end
  end
  return {}
end

M.NegativeConstraint = function(name, ismethod)
  local t = { member = name, pred = ismethod and NegativeMethodPredicate or NegativeFieldPredicate, name = "~"..name }

  function t:equal(b)
    return self.member == b.member
  end
  function t:synthesize()
    return List{nil}
  end
  function t:subset(b, context)
    return self.member == b.member
  end
  return setmetatable(t, Constraint_mt)
end

local function MetatablePredicate(self, obj, context)
  if obj == nil then
    error("Expected metatable "..tostring(self.mt).." but found nil instead!")
  end
  if getmetatable(obj) ~= self.mt then
    error("Expected "..tostring(obj).." to have metatable "..tostring(self.mt).." but found "..tostring(getmetatable(obj)).." instead!")
  end
  return {}
end

-- Checks to see if the metatable belonging to obj equals the expected metatable.
M.MetatableConstraint = function(metatable)
  local t = { mt = metatable, pred = MetatablePredicate, name = "Metatable: "..tostring(metatable) }

  function t:equal(b)
    return self.mt == b.mt
  end
  function t:synthesize()
    return List{setmetatable({}, self.mt)}
  end
  function t:subset(b, context)
    return self.mt == b.mt
  end
  return setmetatable(t, Constraint_mt)
end

local function LuaOperatorPredicate(self, obj, context)
  if obj == nil then
    error "obj cannot be nil"
  end

  local mt = getmetatable(obj)
  if mt == nil then
    error("Metatable for "..tostring(obj).." is nil")
  elseif mt[self.op] == nil then
    error(tostring(obj).." does not have metatable entry "..self.op.." in "..tostring(mt))
  end

  return {}
end

local function TerraOperatorPredicate(self, obj, context)
  if not IsType(obj) or not obj:isstruct() then
    error(tostring(obj).." is not a terra struct and therefore can't have metamethods.")
  end
  if obj.metamethods[self.op] == nil then
    error (tostring(obj).." does not have metamethod "..self.op)
  end

  return {}
end

-- Checks for the existence of a given metamethod, either on a terra type or on a lua table's metatable
M.OperatorConstraint = function(operator, luatable)
  local t = { op = operator, pred = luatable and LuaOperatorPredicate or TerraOperatorPredicate, name = (luatable and "Lua" or "Terra").."Op: "..tostring(operator) }

  function t:equal(b)
    return self.op == b.op
  end
  function t:synthesize()
    if self.pred == LuaOperatorPredicate then
      local mt = {}
      mt[self.op] = true
      return List{setmetatable({}, mt)}
    end

    local s = struct{}
    s.metamethods[self.op] = true
    return List{s}
  end
  function t:subset(b, context)
    return self.op == b.op
  end
  return setmetatable(t, Constraint_mt)
end

-- Generates an appropriate optional version of the constraint, depending on if it's a method, field, or value constraint.
M.Optional = function(constraint)
  if not IsConstraint(constraint) then
    constraint = M.MakeValue(constraint)
  end

  if constraint.pred == FieldPredicate then
    return constraint + M.NegativeConstraint(constraint.field, false)
  elseif constraint.pred == MethodPredicate then
    return constraint + M.NegativeConstraint(constraint.method, true)
  end

  return constraint + M.Value(nil)
end

M.Any = function(...)
  if select("#", ...) == 0 then
    return M.Constraint(Tautalogy, List{tuple()}, "Any")
  end
  return M.MultiConstraint(false, nil, ...)
end

M.All = function(...) return M.MultiConstraint(true, nil, ...) end
M.Number = M.LuaConstraint("number")
M.String = M.LuaConstraint("string")
M.Table = M.LuaConstraint("table")
M.LuaValue = M.LuaConstraint(nil)
M.TerraType = M.TypeConstraint(nil)
M.Function = M.FunctionConstraint
M.Field = M.FieldConstriant
M.Method = M.MethodConstraint
M.Integral = M.Constraint(function(self, obj) if not IsType(obj) or not obj:isintegral() then error (tostring(obj).." is not an integral type") end return {} end, List{int, intptr, uint}, "Integral")
M.Float = M.Constraint(function(self, obj) if not IsType(obj) or not obj:isfloat() then error (tostring(obj).." is not a float type") end return {} end, List{float, double}, "Float")
M.TerraStruct = M.Constraint(function(self, obj) if not IsType(obj) or not obj:isstruct() then error (tostring(obj).." is not a struct") end return {} end, List{struct{}}, "Struct")
M.Pointer = M.PointerConstraint
M.Type = M.TypeConstraint
M.Value = M.ValueConstraint
M.Empty = M.Value(nil)
M.Negative = M.NegativeConstraint
M.Cast = function(e) return M.BasicConstraint(e, true) end
M.Rawstring = M.MakeValue(rawstring)
M.IsConstraint = M.MetatableConstraint(Constraint_mt)
M.LuaOperator = function(e) return M.OperatorConstraint(e, true) end
M.TerraOperator = function(e) return M.OperatorConstraint(e, false) end

-- Mathematically, the first operation is always multiplication, but to prevent confusion, we make the first
-- operation addition. Thus, no consistent object will only have a multiplicative operator.
M.Semigroup = M.TerraOperator("__add")
M.Monoid = M.Semigroup * M.Method("Zero", {}, M.Any())
M.Group = M.Monoid * M.TerraOperator("__sub")
M.Semiring = M.Monoid * M.TerraOperator("__mul") * M.Method("Identity", {}, M.Any())
M.Nearring = M.Group * M.TerraOperator("__mul")
M.Ring = M.Nearring * M.Method("Identity", {}, M.Any())
M.DivisionRing = M.Ring * M.TerraOperator("__div")

M.Comparable = M.TerraOperator("__eq") * M.TerraOperator("__ne")
M.Ordered = M.Comparable * M.TerraOperator("__le") * M.TerraOperator("__lt") * M.TerraOperator("__ge") * M.TerraOperator("__gt")
-- Intended for booleans or bitsets
M.Logical = M.Comparable * M.TerraOperator("and") * M.TerraOperator("or") * M.TerraOperator("not") * M.TerraOperator("xor")

local M_mt = {
  __call = function(self,fn, ...)
    local params = List()

    for i, v in args(...) do 
      params[i] = M.MetaParameter(M.MakeConstraint(v))
    end
    local f = fn(unpack(params))
    f.typeparams = params
    return f
  end
}

return setmetatable(M, M_mt)