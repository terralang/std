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

M.ErrorResult = macro(function(err)
	return `[M.MakeErrorResult(err:gettype())] {[err]}
end)

M.MakeResult = terralib.memoize(function(OkayType, ErrorType)
	local enum Result {
		ok: OkayType,
		err: ErrorType
	}
	BlessResult(Result, OkayType, ErrorType)

	-- Applies the function to the ok value, leaving the err value untouched
	Result.methods.map = macro(function(self, fn)
		-- Extracting the type from the fn quote
		local fn_type = fn:gettype()
	
		if fn_type:ispointertofunction() then
			fn_type = fn_type.type
		end

		-- Typechecking
		if not fn_type:isfunction() then
			error("type error: expected parameter `fn` to be a function or function pointer, got `" .. tostring(fn_type) .. "`.")
		elseif #fn_type.parameters ~= 1 then
			error("type error: expected function `fn` to take only one parameter, got " .. #fn_type.parameters .. ".")
		elseif fn_type.parameters[0] == OkayType then
			error("type error: expected function `fn` to take a parameter of type '" .. tostring(self.type_parameters.OkayType) .. ", got " .. tostring(fn_type.parameters[0]) .. ").")
		end

		local return_type = M.MakeResult(fn_type.returntype, ErrorType)

		return quote
			var this = self
			var return_value: return_type
			if this:is_ok() then
				return_value = [return_type].ok([fn](this.ok))
			else
				return_value = [return_type].err(this.err)
			end
		in return_value end
	end)

	-- If an Ok value, returns the Ok value, otherwise this will force the calling function to return with an ErrorResult
	Result.methods.unwrap = macro(function(self) 
		return quote 
			var this = self
			if this:is_err() then
				return M.ErrorResult(this.err) 
			end 
		in this.ok end 
	end)

	return Result
end)

return M
