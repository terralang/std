local O = require 'std.object'
local HT = require 'std.hashtable'
local C = terralib.includec("stdio.h")
local CStr = terralib.includec("string.h")
local Alloc = require 'std.alloc'

describe("_Plumbing.table_calloc", function()
	local StringHashTableModule = HT.CreateHashTableSubModule(rawstring)
	local Plumbing = StringHashTableModule._Plumbing

	it("should allocate enough memory and initalize the metadata portion", terra()
		var capacity = 8
		var alloc_success, opaque_ptr, metadata_array, buckets_array = Plumbing.table_calloc(capacity)

		assert.is_true(alloc_success)
		assert.is_true(opaque_ptr ~= nil)

		for i = 0, capacity do
			assert.equal(metadata_array[i], 128)
		end

		Alloc.free(opaque_ptr)
	end)
end)

describe("_Plumbing.probe", function()
	local StringHashTableModule = HT.CreateHashTableSubModule(rawstring)
	local Plumbing = StringHashTableModule._Plumbing

	it("should use initial_bucket_index if the bucket is empty", terra()
		var test_key = "look at the sky"
		var test_hash_result = Plumbing.HashResult {
			initial_bucket_index = 5,
			h1 = 0,
			h2 = 69
		}
		var test_metadata_array = arrayof(uint8, 128, 128, 128, 128, 128, 128, 128, 128)
		var test_buckets_array = arrayof(rawstring, "0", "0", "0", "0", "0", "0", "0", "0")

		var actual_index = Plumbing.probe(test_key, test_hash_result, test_metadata_array, test_buckets_array, 8)

		assert.equal(actual_index, test_hash_result.initial_bucket_index)
	end)

	it("should iterate through the buckets if initial_bucket_index is full", terra()
		var test_key = "i'm still here"
		var test_hash_result = Plumbing.HashResult {
			initial_bucket_index = 2,
			h1 = 0,
			h2 = 70
		}
		var test_metadata_array = arrayof(uint8, 128, 1, 2, 3, 4, 128, 128, 128)
		var test_buckets_array = arrayof(rawstring, "0", "0", "0", "0", "0", "0", "0", "0")

		var actual_index = Plumbing.probe(test_key, test_hash_result, test_metadata_array, test_buckets_array, 8)

		assert.equal(actual_index, 5)
	end)

	it("should wrap around while probing", terra()
		var test_key = "i'll be alive next year"
		var test_hash_result = Plumbing.HashResult {
			initial_bucket_index = 2,
			h1 = 0,
			h2 = 71
		}
		var test_metadata_array = arrayof(uint8, 128, 1, 2, 3, 4, 6, 7, 8)
		var test_buckets_array = arrayof(rawstring, "0", "0", "0", "0", "0", "0", "0", "0")

		var actual_index = Plumbing.probe(test_key, test_hash_result, test_metadata_array, test_buckets_array, 8)

		assert.equal(actual_index, 0)
	end)

	it("should return -1 if full", terra()
		var test_key = "i can make something good"
		var test_hash_result = Plumbing.HashResult {
			initial_bucket_index = 2,
			h1 = 0,
			h2 = 72
		}
		var test_metadata_array = arrayof(uint8, 9, 1, 2, 3, 4, 6, 7, 8)
		var test_buckets_array = arrayof(rawstring, "0", "0", "0", "0", "0", "0", "0", "0")

		var actual_index = Plumbing.probe(test_key, test_hash_result, test_metadata_array, test_buckets_array, 8)

		assert.equal(actual_index, -1)
	end)

	it("should return -1 if initial_bucket_index is invalid", terra()
		var test_key = "something good"
		var test_hash_result = Plumbing.HashResult {
			initial_bucket_index = 45,
			h1 = 0,
			h2 = 73
		}
		var test_metadata_array = arrayof(uint8, 9, 1, 2, 3, 4, 6, 7, 8)
		var test_buckets_array = arrayof(rawstring, "0", "0", "0", "0", "0", "0", "0", "0")

		var actual_index = Plumbing.probe(test_key, test_hash_result, test_metadata_array, test_buckets_array, 8)

		assert.equal(actual_index, -1)
	end)
end)

describe("HashTable", function()

	it("should initalize metadata to MetadataEmpty", terra()
		var hash_table: HT.HashTable(rawstring)
		O.new(hash_table)

		-- Assert that metadata is initalized
		for i = 0, hash_table.capacity do
			assert.equal(hash_table.metadata[i], 128)
		end
	end)

	-- We should add a copy constructor and a capacity constructor.
	
	it("should insert entries", terra()
		var hash_table: HT.HashTable(rawstring)
		O.new(hash_table)
		
		var str1 = "According to all known laws of aviation"
		var str2 = "there is no way that a be should be able to fly"
		var str3 = "Its wings are too small to get its fat little body off the ground"
		hash_table:insert(str1)
		hash_table:insert(str2)
		hash_table:insert(str3)
		
		assert.equal(hash_table.size, 3)
		assert.is_true(hash_table:has(str1))
		assert.is_true(hash_table:has(str2))
		assert.is_true(hash_table:has(str3))

	end)


	it("should resize automatically when enough entries are added", terra()
		var hash_table: HT.HashTable(rawstring)
		O.new(hash_table)

		var initial_capacity = hash_table.capacity
		for i = 0, (initial_capacity + 3) do
			var string_buffer = Alloc.calloc([int8], 10)
			C.snprintf(string_buffer, 10, "i: %d", i)
			hash_table:insert(string_buffer)
		end
		
		hash_table:debug_full_repr()

		assert.is_true(hash_table.capacity > initial_capacity)

		for i = 0, hash_table.capacity do
			if hash_table.metadata[i] ~= 128 then
				Alloc.free(hash_table.buckets[i])
			end
		end
	end)
end)
