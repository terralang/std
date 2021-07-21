local R = require "std.result"
local Cio = terralib.includec("stdio.h")

local TestResult = R.MakeResult(double, int)

describe("ErrorResult", function()
	local TestError = R.MakeErrorResult(TestResult.type_parameters.ErrorType)

	it("can be casted to a full Result type", terra()
		var from: TestError = TestError { 709 }
		var to: TestResult = [TestResult](from)

		assert.is_true(to:is_err())
		assert.equal(709, to.err)
	end)
end)

describe("OkayResult", function()
	local TestOkay = R.MakeOkayResult(TestResult.type_parameters.OkayType)

	it("can be casted to a full Result type", terra()
		var from: TestOkay = TestOkay { 147.762 }
		var to: TestResult = [TestResult](from)

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

	it("can check which alternative it is", terra()
		var okay = TestResult.ok(42.3)
		var err = TestResult.err(76)

		assert.is_true(okay:is_ok())
		assert.is_false(okay:is_err())

		assert.is_false(err:is_ok())
		assert.is_true(err:is_err())
	end)
end)
