

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
        return `[getfn()]([args])
    end,
    function(...)
        return getfn()(...)
    end)
end