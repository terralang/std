local O = require 'std.object'
local HashTable = require 'std.hashtable'
local C = terralib.includec("stdio.h")

describe("Hash table", function()
	local StringHashTable = HashTable(rawstring)
	
	it("should have a default constructor", terra()
		var hash_table: StringHashTable
		O.new(hash_table)
	end)

	-- We should add a copy constructor and a capacity constructor.

	it("should insert entries", terra()
		var hash_table: StringHashTable
		O.new(hash_table)

		hash_table:insert("rawr")
		hash_table:insert("X3")
		hash_table:insert("OwO")

		for i = 0, hash_table.capacity do
			C.printf("[%d] %x\t", i, hash_table.metadata[i])
			if hash_table.metadata[i] == 128 then
				C.printf("Empty\n")
			else
				C.printf("%s\n", hash_table.buckets[i])
			end
		end

		assert hash_table:has("rawr")
		assert hash_table:has("X3")
		assert hash_table:has("OwO")

	end)
end)
