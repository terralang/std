local Str = require 'std.string'
local HashTable = require 'std.hashtable'

describe("Hash table", function()
	local StringHashTable = HashTable(Str)
	it("should have a constructor", terra()
		var hash_table: HT
		hash_table.init()
	end)
end)
