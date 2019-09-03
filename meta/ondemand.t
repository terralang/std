

return function(fn)
    local cached = false
    local cachefn = nil
    local function getfn()
        if not cached then
            cached, cachefn = true, fn()
        end
        return cachefn
    end
    return macro(function(...)
        local args = {...}
        if #args > 0 then -- heuristics for a method call.
            local selftype = args[1]:gettype() --heuristic for automatic enreference insertion on method calls
            if not selftype:ispointer() and args[1]:islvalue() and terralib.isfunction(getfn()) and getfn().type.parameters[1]:ispointer() then
                args[1] = `&[args[1] ]
            end
        end
        return `[getfn()]([args])
    end,
    function(...)
        return getfn()(...)
    end)
end