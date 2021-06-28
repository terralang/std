local O = require 'std.object'
local HashTable = require 'std.hashtable'
local C = terralib.includec("stdio.h")

describe("Hash table", function()
	local StringHashTable = HashTable(rawstring)

	local terra debug_print_hashtable(hash_table: StringHashTable)
		for i = 0, hash_table.capacity do
			C.printf("[%d]\t%0#2X\t", i, hash_table.metadata[i])
			if hash_table.metadata[i] == 128 then
				C.printf("Empty\n")
			else
				C.printf("%s\n", hash_table.buckets[i])
			end
		end
	end

	it("should have a default constructor", terra()
		var hash_table: StringHashTable
		O.new(hash_table)
	end)

	-- We should add a copy constructor and a capacity constructor.

	it("should insert entries", terra()
		var hash_table: StringHashTable
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
end)
