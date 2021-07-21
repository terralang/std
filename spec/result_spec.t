local R = require "std.result"
local Cio = terralib.includec("stdio.h")

local TestResult = R.MakeResult(double, int)

describe("ErrorResult", function()
	local TestError = R.MakeErrorResult(TestResult.type_parameters.ErrorType)

	it("can be casted to a full Result type", terra()
		var from: TestError = TestError.err(708)
		Cio.printf("from: %d\n", from.err)
		-- Implicit casts don't work for structs it seems
		var to: TestResult = [TestResult](from)

		--[[
		assert.is_true(to:is_err())
		assert.equal(709, to.err) ]]--
	end)
end)

describe("OkayResult", function()
	local TestOkay = R.MakeOkayResult(TestResult.type_parameters.OkayType)

	it("can be casted to a full Result type", terra()
		var from: TestOkay = TestOkay.ok(147.762)
		var to = [TestResult](from)

		assert.is_true(to:is_ok())
		assert.equal(147.762, to.ok)
	end)
end)

describe("std.result", function()
	local TestOkay = R.MakeOkayResult(double)
	local TestError = R.MakeErrorResult(int)

	it("can be instantiated in both okay and error alternatives", terra()
		var okay = TestResult.ok(42.3)
		var err = TestResult.err(76)
	end)

end)
