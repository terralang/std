local R = require "std.result"
local String = require "std.string"

local TestResult = R.MakeResult(double, int)

describe("ErrorResult", function()
	local TestError = R.MakeErrorResult(TestResult.type_parameters.ErrorType)

	it("can be casted to a full Result type", terra()
		var from: TestError = TestError { 709 }
		var to: TestResult = from -- Implicit cast

		assert.is_true(to:is_err())
		assert.equal(709, to.err)
	end)

	it("reports is_err and is_ok correctly", terra()
		var sut = TestError { 709 }

		assert.is_true(sut:is_err())
		assert.is_false(sut:is_ok())
	end)
end)

describe("OkayResult", function()
	local TestOkay = R.MakeOkayResult(TestResult.type_parameters.OkayType)

	it("can be casted to a full Result type", terra()
		var from: TestOkay = TestOkay { 147.762 }
		var to: TestResult = from -- Implicit cast

		assert.is_true(to:is_ok())
		assert.equal(147.762, to.ok)
	end)

	it("reports is_err and is_ok correctly", terra()
		var sut = TestOkay { 147.762 }

		assert.is_true(sut:is_ok())
		assert.is_false(sut:is_err())
	end)
end)

describe("std.result", function()
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

	it("can be mapped with a function", function()
		local terra double_to_string(x: double): String
			return String.Format("%d", x)
		end

		local terra map_test_function_pointer()
			var sut = TestResult.ok(42.3)

			var actual = sut:map(double_to_string)
			var expected: String
			expected:init("42.3")


			assert.is_true(actual:is_ok())
			assert.equal(expected, actual.ok)
		end

		map_test_function_pointer()
	end)

	it("can be unwrapped", function()
		local terra unwrap_ok_same_type(): TestResult
			var sut = TestResult.ok(42.3)
			var x = sut:unwrap() + 1
			
			assert.equal(43.3, x)
		end

		local terra unwrap_err_compatabile_type(): R.MakeResult(String, int)
			var sut = TestResult.err(10)
			var x = sut:unwrap() + 1
		end

		unwrap_ok_same_type()

		assert.equal(10, unwrap_err_compatabile_type().err)
	end)
end)
