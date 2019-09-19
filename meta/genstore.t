
local function genstore(desc, typedef)
  local constants, variables = {}, {}
  for k, v in pairs(desc) do
    if terralib.isquote(v) then
      local val, err = v:asvalue()
      if (val or not err) and not terralib.issymbol(val) then
        constants[k] = val
      else
        table.insert(variables, {k, v})
      end
    else
      constants[k] = v
    end
  end
    --TODO: memoize this type creation
  table.sort(variables, function(a, b) return terralib.sizeof(a[2]:gettype()) > terralib.sizeof(b[2]:gettype()) end)
  local storetype = terralib.types.newstruct()
  local initializers = {}
  for i, v in ipairs(variables) do
    storetype.entries[i] = {v[1], v[2]:gettype()}
    initializers[i] = v[2]
  end
  for k, v in pairs(constants) do
    storetype.methods[k] = v
  end
  if typedef then
    if type(typedef) == "function" then
      typedef(storetype)
    elseif type(typedef) == "string" then
      storetype.name = typedef
    else
      error "invalid auxiliary type information provided to genstore"
    end
  end
  return `[storetype] {[initializers]}
end

return genstore
