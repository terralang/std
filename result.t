import "std.enum"

local CT = require 'std.constraint'

local M = {}

-- Adds metaprogramming values to the the provded ResultType, to distinguish it as a Result.
local function BlessResult(ResultType, OkayType, ErrorType)
	ResultType.is_result = true
	ResultType.type_parameters = { OkayType = OkayType, ErrorType = ErrorType }

	-- Add is_err() to the struct if it doesn't exist.
	-- This mainly exists so the partial results can have a similar query API to the full result
	if ResultType.methods.is_err == nil then
		terra ResultType:is_err()
			return [ ErrorType ~= nil ]
		end
	end

	if ResultType.methods.is_ok == nil then
		terra ResultType:is_ok()
			return [ OkayType ~= nil ]
		end
	end
end

local function MakeBaseErrorString(from, to)
	return "Invalid cast from " .. tostring(from) .. " to " .. tostring(to) .. ":"
end

local function AssertCastingToResultType(from, to)
	if to.is_result ~= true then
		error(MakeBaseErrorString(from, to) .. " Cannot convert from result to non-result type.")
	end
end

local function AssertCastingTypeParamEqual(from, to, param_name, expected_value)
	if to.type_parameters[param_name] ~= expected_value then
		error(MakeBaseErrorString(from, to) .. " Type parameter " .. param_name .. " mismatched.")
	end
end

-- A result that can only be an okay
M.MakeOkayResult = terralib.memoize(function(OkayType)
	local struct OkayResult {
		ok: OkayType
	}
	BlessResult(OkayResult, OkayType, nil)

	function OkayResult.metamethods.__cast(from, to, expr)
		AssertCastingToResultType(from, to)
		AssertCastingTypeParamEqual(from, to, "OkayType", OkayType)
		return `[to].ok([expr].ok)
	end

	return OkayResult
end)

-- A result that can only be an error
M.MakeErrorResult = terralib.memoize(function(ErrorType)
	local struct ErrorResult {
		err: ErrorType
	}
	BlessResult(ErrorResult, nil, ErrorType)

	function ErrorResult.metamethods.__cast(from, to, expr)
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
