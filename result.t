import "std.enum"

local CT = require 'std.constraint'

local M = {}

-- Adds metaprogramming values to the the provded ResultType, to distinguish it as a Result.
local function BlessResult(ResultType, OkayType, ErrorType)
	ResultType.is_result = true
	ResultType.type_parameters = { OkayType = OkayType, ErrorType = ErrorType }
end

local function MakeBaseErrorString(from, to)
	return "Invalid cast from " .. tostring(from) .. " to " .. tostring(to) .. ":"
end

local function AssertCastingToResultType(from, to)
	if to.is_result != true then
		error(MakeBaseErrorString(from, to) .. " Cannot convert from result to non-result type.")
	end
end

local function AssertCastingTypeParamEqual(from, to, param_name, expected_value)
	if to[param_name] != expected_value then
		error(MakeBaseErrorString(from, to) .. " Type parameter " .. param_name .. "mismatched.")
	end
end

-- A result that can only be an okay
M.MakeOkayResult = terralib.memoize(function(OkayType)
	local enum OkayResult {
		ok: OkayType
	}
	BlessResult(OkayResult, OkayType, nil)

	function OkayType.metafunctions.__cast(from, to, expr)
		AssertCastingToResultType(from, to)
		AssertCastingTypeParamEqual(from, to, "OkayType", OkayType)
		return `[to].ok([expr].ok)
	end

	return OkayType
end)

-- A result that can only be an error
M.MakeErrorResult = terralib.memoize(function(ErrorType)
	local enum ErrorResult {
		err: ErrorType
	}
	BlessResult(ErrorResult, nil, ErrorType)

	function ErrorResult.metafunctions.__cast(from, to, expr)
		AssertCastingToResultType(from, to)
		AssertCastingTypeParamEqual(from, to, "ErrorType", ErrorType)
		return `[to].err([expr].err)
	end

	return ErrorResult
end)

M.MakeResult = terralib.memoize(function(OkayType, ErrorType)
	local enum Result {
		ok: OkayType,
		err: ErrorType
	}
	BlessResult(Result, OkayType, ErrorType)

	Result.apply = macro(function(self, fn)
		
	end)

	Result.unwrap = macro(function(self) 
		return quote 
			var s = self
			if s:is_ok() then
				return s 
			end 
		in s.ok end 
	end)

	return Result
end)

return M
