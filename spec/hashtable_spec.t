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

		var a = hash_table:entry("rawr")
		var b = hash_table:entry("X3")
		var c = hash_table:entry("OwO")

		C.printf("[a] %x - %s\n", @a.metadata, @a.bucket)
		C.printf("[b] %x - %s\n", @b.metadata, @b.bucket)
		C.printf("[c] %x - %s\n", @c.metadata, @c.bucket)
	end)
end)
