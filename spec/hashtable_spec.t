local O = require 'std.object'
local HashTable = require 'std.hashtable'

describe("Hash table", function()
	local StringHashTable = HashTable(rawstring)
	
	it("should have a default constructor", terra()
		var hash_table: HT
		O.new(hash_table)
	end)

	-- We should add a copy constructor and a capacity constructor.

	it("should insert and retrieve entries", terra()
		var hash_table: HT
		O.new(hash_table)

		hash_table.insert("rawr")
		hash_table.insert("X3")
		hash_table.insert("OwO")

		hash_table.entry("rawr")
		hash_table.entry("X3")
		hash_table.entry("OwO")
	end)
end)
