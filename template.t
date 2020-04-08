local tunpack = table.unpack or unpack

return function (body)
  local genfun = terralib.memoize(body)
  return macro(function(...)
    local args = terralib.newlist{...}
    local types = args:map(function(x) return x:gettype() end)
    local resfun = genfun(tunpack(types))
    return `resfun([args])
  end)
end