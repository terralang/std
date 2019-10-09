local List = require 'terralist'

return macro(function(expr, ...)
    local cases = List()
    local ordefault = nil

    local function build(condition, expression, ...)
        if condition ~= nil then
            if expression == nil then condition, expression = expression, condition end

            if condition ~= nil then
                local case = terralib.irtypes.switchcase(condition.tree, terralib.irtypes.block(expression.tree.statements))
                case.filename, case.linenumber, case.offset = expression.filename, expression.linenumber, expression.offset
                cases:insert(case)
                build(...)
            else
                ordefault = expression
            end
        end
    end
    build(...)

    local q = terralib.irtypes.switchstat(expr.tree, cases, terralib.irtypes.block(ordefault.tree.statements))
    q.filename, q.linenumber, q.offset = expr.filename, expr.linenumber, expr.offset
    q.type = tuple()
    return terralib.newquote(q)
end)
