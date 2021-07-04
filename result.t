import "std.enum"

local M = {}

function M.MakeOption(T)
	local enum Option {
		none,
		some: T
	}
	
	return Option
end

function M.MakeResult(ResultType, FailureType)
	local enum Result {
		result: ResultType,
		failure: FailureType
	}

	return Result
end

return M
