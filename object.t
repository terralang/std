local ondemand = require 'std.meta.ondemand'

local M = {}

M.initializer = terralib.memoize(function(base, it)
    if it == nil then
        local self_entries = base:getentries()
        return terra(self : &base)
            escape
                for i, ent in ipairs(self_entries) do
                    emit `M.init(self.[self_entries[i].field])
                end
            end
        end
    elseif it.convertible == "tuple" then
        local self_entries = base:getentries()
        local init_entries = it:getentries()
        if #self_entries ~= #init_entries then
            error "member initialization list doesn't match object entries in length"
        end

        return terra(self : &base, initializer : it)
            escape
                for i, ent in ipairs(init_entries) do
                    emit `M.init(self.[self_entries[i].field], initializer.[ent.field])
                end
            end
        end
    elseif it.convertible == "named" then
        local self_entries = base:getentries()

        return terra(self : &base, initializer : it)
            escape
                for i, ent in ipairs(self_entries) do
                    if it:getfield(ent.field) then
                        emit `M.init(self.[ent.field], initializer.[ent.field])
                    else
                        emit `M.init(self.[ent.field])
                    end
                end
            end
        end
    else
        error "invalid initializer list"
    end
end)

M._init = macro(function(self, value)
    if not self:gettype():ispointer() then
        self = `&self
    end
    if value ~= nil then
        return quote [M.initializer(self:gettype().type, value:gettype())](self, value) end
    else 
        return quote [M.initializer(self:gettype().type)](self) end
    end
end)

M.init = macro(function(self, value)
    if self:gettype():isaggregate() then
        if self:gettype():getmethod("init") then
            if value ~= nil and value:gettype() ~= terralib.types.unit then
                return quote var v = value; self:init(terralib.unpacktuple(v)) end
            else
                return `self:init()
            end
        else
            return `M._init(self, value)
        end
    elseif value ~= nil then -- If this isn't an aggregate type, we simply attempt to set it equal to the init value
        return quote 
            var _self = &self
            (@_self) = [value]
        end
    end
end)

M.destructor = terralib.memoize(function(T)
    if T:isstruct() then
        return terra(self : &T)
            escape
                local entries = T:getentries()
                for _, entry in ipairs(entries) do
                    if entry.field and entry.type:isaggregate() then -- Only generate a destructor if it isn't a union and it's an aggregate type
                        emit `M.destruct(self.[entry.field])
                    end
                end
            end
        end
    elseif T:isarray() and T.type:isaggregate() then
        return terra(self : &T)
            var pa = &self
            for i = 0,T.N do
                M.destruct((@pa)[i])
            end
        end
    end
    return quote end
end)

M.destruct = macro(function(self)
    if not self:gettype():ispointer() then
        self = `&self
    end
    local T = self:gettype().type
    if T:isaggregate() then
        if T:isstruct() and T:getmethod("destruct") then
            return `self:destruct()
        end
        return quote [M.destructor(T)](self) end
    end
    return quote end
end)


M.op_copy = terralib.memoize(function(T)
    if T:isstruct() then
        return terra(self : &T, arg : &T)
            escape
                for _, entry in ipairs(entries) do
                    emit `M.copy(self.[entry.field], arg.[entry.field])
                end
            end
        end
    elseif T:isarray() and T.type:isaggregate() then
        return terra(self : &T, arg : &T)
            var pa = &self
            var pb = &arg
            for i = 0,T.N do
                M.copy((@pa)[i], (@pb)[i])
            end
        end
    end
    return quote 
        var _self = &self
        (@_self) = [arg]
    end
end)

M.copy = macro(function(self, arg)
    if not self:gettype():ispointer() then
        self = `&self
    end
    local T = self:gettype().type
    if T:isaggregate() then
        if T:isstruct() and T:getmethod("copy") then
            return `self:copy(arg)
        end
        return quote [M.op_copy(T)](self, arg) end
    end
    return quote end
end)

--setmetatable(M, {__call = function(base)
function M.Object(base)
    base.methods._init = M._init
    if not base.methods.destruct then -- Terra is inconsistent about when it runs this function
        base.methods.destruct = M.destructor(base)
    end
end

M.new = macro(function(T, ...)
    local args = {...}
    if terralib.types.istype(T:asvalue()) then
        if terralib.isquote(T) then
            T = T:astype()
        end
        
        return quote 
            var v : T
            M.init(v, {[args]})
            defer M.destruct(v)
        in 
            v
        end
    end
    
    return quote 
        M.init(T, {[args]})
        defer M.destruct(T)
    end
end)

M.construct = macro(function(v, ...)
    local args = {...}
    
    return `M.init(v, {[args]})
end)

-- Wraps a function call in a destruct macro. The macro calls the function, assigns the result to a variable,
-- defers a destruction method, and returns the result. Used in functions that need to return objects, like a string.
-- The object CANNOT BE MODIFIED or the destructor will be wrong.
M.destroy = function(f)
    if terralib.isfunction(f) and #f.definition.parameters > 0 and f.definition.parameters[1].name == "self" then
        return macro(function(s, ...)
            local args = {...}
            if not s:gettype():ispointer() then
                s = `&s
            end
            return quote 
                var v = f(s, [args])
                defer M.destruct(v)
            in
                v
            end
        end)
    elseif terralib.isquote(f) then
        return quote 
            var v = f
            defer M.destruct(v)
        in
            v
        end
    else
        return macro(function(...)
            local args = {...}
            return quote 
                var v = f([args])
                defer M.destruct(v)
            in
                v
            end
        end)
    end
end

-- Recursively sets all pointers to null in a type so that the destructor does nothing
M.move = macro(function(self)
    if self:gettype():isaggregate() then
        local self_entries = base:getentries()
        return quote
            escape
                for i, ent in ipairs(self_entries) do
                    emit `M.move(self.[self_entries[i].field])
                end
            end
        end
    elseif self:gettype():ispointer() then
        return quote self = nil end
    end
end)

return M