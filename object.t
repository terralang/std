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

M._init = macro(function(self, init)
    if not self:gettype():ispointer() then
        self = `&self
    end
    if init ~= nil then
        local fn = M.initializer(self:gettype().type, init:gettype())
        return quote fn(self, init) end
    else 
        local fn = M.initializer(self:gettype().type)
        return quote fn(self) end
    end
end)

M.init = macro(function(self, ...)
    local args = {...}
    local init = args[1]
    if self:gettype():isaggregate() then
        if self:gettype():getmethod("init") then
            if select("#", ...) > 0 then
                return `self:init([...])
            else
                return `self:init()
            end
        else
            return `M._init(self, init)
        end
    elseif init ~= nil then -- If this isn't an aggregate type, we simply attempt to set it equal to the init value
        return quote 
            var _self = &self
            (@_self) = [init]
        end
    end
end)

M.destructor = terralib.memoize(function(T)
    if T:isstruct() then
        return terra(self : &T)
            escape
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
    local T = self:gettype()
    if T:isaggregate() then
        if T:isstruct() and T:getmethod("destruct") then
            return `self:destruct()
        end
        local fn = M.destructor(self:gettype())
        return quote fn(self) end
    end
    return quote end
end)

return M