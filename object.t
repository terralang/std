local ondemand = require 'std.meta.ondemand'

local M = {}

M._init = macro(function(self, init)
    local it = init:gettype()
    local self_entries = self:gettype():getentries()
    if it.convertible == "tuple" then
        local init_entries = it:getentries()
        if #self_entries ~= #init_entries then
            error "member initialization list doesn't match object entries in length"
        end
        return quote
            var initializer = [init]
            var _self = &self
            escape
                for i, ent in ipairs(init_entries) do
                    local ftype = ent.type
                    if ftype:isstruct() and ftype:getmethod "init" then
                        emit quote (@_self).[self_entries[i].field]:init(terralib.unpacktuple(initializer.[ent.field])) end
                    else
                        emit quote (@_self).[self_entries[i].field] = initializer.[ent.field] end
                    end
                end
            end
        end
    elseif it.convertible == "named" then
        local init_entries = it:getentries()
        return quote
            var initializer = [init]
            var _self = &self
            escape
                for i, ent in ipairs(init_entries) do
                    local ftype = ent.type
                    if ftype:isstruct() and ftype:getmethod "init" then
                        emit quote (@_self).[ent.field]:init(terralib.unpacktuple(initializer.[ent.field])) end
                    else
                        emit quote (@_self).[self_entries[i].field] = initializer.[ent.field] end
                    end
                end
            end
        end
    else
        error "invalid initializer list"
    end
end)

--large sections of this logic from terra/lib/std.t

M.run_deinit = macro(function(self)
    local T = self:gettype()
    local function hasdtor(T) --avoid generating code for empty array destructors
        if T:isstruct() then return T:getmethod("deinit") 
        elseif T:isarray() then return hasdtor(T.type) 
        else return false end
    end
    if T:isstruct() then
        local d = T:getmethod("deinit")
        if d then
            return `self:deinit()
        end
    elseif T:isarray() and hasdtor(T) then        
        return quote
            var pa = &self
            for i = 0,T.N do
                M.run_deinit((@pa)[i])
            end
        end
    end
    return quote end
end)

M.generate_deinit = macro(function(self)
    local T = self:gettype()
    local entries = T:getentries()
    return quote
        escape
            for _, ent in ipairs(entries) do
                if ent.field then -- check that it isn't a union
                    emit `M.run_deinit(self.[ent.field])
                end
            end
        end
    end
end)

function M.Object(base)
    base.methods._init = M._init
    base.methods.deinit = ondemand(function()
        return terra(self: &base)
            M.generate_deinit(@self)
        end
    end)
end

return M