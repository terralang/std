local O = require 'std.object'
local HT = require 'std.hashtable'
local CIO = terralib.includec("stdio.h")
local CStr = terralib.includec("string.h")
local Alloc = require 'std.alloc'

describe("Implementation.DenseHashTable HashSet", function()
	local IntegerHashSet = HT.Implementation.DenseHashTable(int, nil, HT.CreateDefaultHashFunction(int), HT.CreateDefaultEqualityFunction(int), Alloc.default_allocator)

	it("should allow you to insert items", terra()
		var hash_set: IntegerHashSet
		O.new(hash_set)
 
		var expected = 621
		var handle = hash_set:lookup_handle(expected)
		var store_result = hash_set:store_handle(handle, expected)

		assert.is_true(store_result == 0)
	end)

end)

describe("Implementation.DenseHashTable HashMap", function()
	local StringHashMap = HT.Implementation.DenseHashTable(rawstring, rawstring, HT.CreateDefaultHashFunction(rawstring), HT.CreateDefaultEqualityFunction(rawstring), Alloc.default_allocator)
	
	it("should allow you to insert items", terra()
		var hash_map: StringHashMap
		O.new(hash_map)

		var expected_key1 = "Summer Kennedy"
		var expected_value1 = "Oh My My"

		var expected_key2 = "Des Rocs"
		var expected_value2 = "Living Proof"

		var handle1 = hash_map:lookup_handle(expected_key1)
		var handle2 = hash_map:lookup_handle(expected_key2)

		var store_result1 = hash_map:store_handle(handle1, expected_key1, expected_value1)
		var store_result2 = hash_map:store_handle(handle2, expected_key2, expected_value2)

		assert.is_true(store_result1 == 0)
		assert.is_true(store_result2 == 0)

		hash_map:debug_full_repr()
	end)
end)
