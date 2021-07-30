local ondemand = require 'meta.ondemand'

local M = {}

M.name = "enum"

M.entrypoints = {"enum"}

M.keywords = {}

--TODO: figure out a better syntax for this
local function annotations(self, lex)
  local annots = terralib.newlist()
  local startingline = lex:cur().linenumber
  if not lex:nextif "(" then
    return annots
  end
  if lex:nextif ")" then
    return annots
  end
  annots:insert(lex:luaexpr())
  while lex:nextif"," do
    annots:insert(lex:luaexpr())
  end
  lex:expectmatch(")", "(", startingline)
  return annots
end

local function K_unit() return terralib.types.unit end

local function alternative(self, lex)
  local name = lex:next().value
  -- print("alternative", name)
  local annots = annotations(self, lex)
  local type = K_unit
  if lex:nextif ":" then
    -- print "parsing type for alternative"
    type = lex:luaexpr()
  end
  return {name = name, annots = annots, type = type}
end


local function alternatives(self, lex)
  local start = lex:expect "{"
  local alts = terralib.newlist()
  if lex:nextif "}" then
    return alts
  end
  repeat
    alts:insert(alternative(self, lex))
    -- terralib.printraw(lex:cur())
  until not lex:nextif ","
  lex:expectmatch("}", "{", start.linenumber)
  return alts
end

local function annot_env(env)
  return function(a)
    a(env)
  end
end

local function build_enum(tree, env)
  local ae = annot_env(env)
  local annots = tree.annots:map(ae)
  local alts = tree.alts:map(function(alt)
      local annots = alt.annots:map(ae)
      -- terralib.printraw(alt)
      return annots:fold({name = alt.name, type = alt.type(env)}, function(alt, annot) return annot(alt) end)
  end)
  local enum = terralib.types.newstruct(tree.name)
  if tree.name then env[tree.name] = enum end
  enum.entries:insert{field = "alt", type = int}
  enum.alternative_types = {}
  enum.entries:insert(
    alts:map(function(alt)
        local ent = {field = alt.name, type = alt.type}
        -- terralib.printraw(ent)
        return ent
    end)
  )
  enum.convertible = "enum"
  enum.enum_values = {}
  for i, v in ipairs(alts) do
    enum.enum_values[v.name] = i-1
    --use ondemand to delay method typechecking to allow metainformation to be added prior to finalization.
    enum.methods["is_"..v.name] = ondemand(function() return terra(self: enum) return self.alt == [i - 1] end end)
    local argsym = symbol(v.type)
    -- terralib.printraw(enum)
    enum.methods[v.name] = ondemand(function() return terra([argsym]) return [enum]{alt = [i - 1], [v.name] = [argsym]} end end)
  end
  enum = tree.annots:fold(enum, function(enum, annot) return annot(enum) end)

  return enum
end

function M.expression(self, lex)
  lex:expect("enum")
  local annots = annotations(self, lex)
  local alts = alternatives(self, lex)
  local tree = {alts = alts, annots = annots}
  return function(environment_function)
    local env = environment_function()
    return build_enum(tree, env)
  end
end

function M.statement(self, lex)
  -- terralib.printraw(lex:cur())
  lex:expect("enum")
  local name = lex:expect(lex.name).value
  local annots = annotations(self, lex)
  local alts = alternatives(self, lex)
  local tree = {name = name, annots = annots, alts = alts}
  return function(environment_function)
    local env = environment_function()
    return build_enum(tree, env)
  end, {name}
end

M.localstatement = M.statement

return M
