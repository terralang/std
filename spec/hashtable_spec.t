local O = require 'std.object'
local HT = require 'std.hashtable'
local C = terralib.includec("stdio.h")
local Alloc = require 'std.alloc'

describe("Hashtable plumbing", function()
	
end)

describe("Hash table", function()

	it("should have a default constructor", terra()
		var hash_table: HT.HashTable(rawstring)
		O.new(hash_table)
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
		
		hash_table:debug_repr()

		assert.equal(hash_table.size, 3)
		assert.is_true(hash_table:has(str1))
		assert.is_true(hash_table:has(str2))
		assert.is_true(hash_table:has(str3))

	end)

	--[[
	it("should resize automatically when enough entries are added", terra()
		var hash_table: StringHashTable
		O.new(hash_table)

		var initial_capacity = hash_table.capacity
		for i = 0, (initial_capacity + 3) do
			var string_buffer = Alloc.calloc([int8], 10)
			C.snprintf(string_buffer, 10, "i: %d", i)
			hash_table:insert(string_buffer)

			C.printf("Hashtable size: %d capacity: %d\n", hash_table.size, hash_table.capacity)
		end
		
		debug_print_hashtable(hash_table)

		assert.is_true(hash_table.capacity > initial_capacity)

		for i = 0, hash_table.capacity do
			if hash_table.metadata[i] ~= 128 then
				Alloc.free(hash_table.buckets[i])
			end
		end
	end) ]]--
end)
