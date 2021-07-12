local HT = require 'std.hashtable'
local O = require 'std.object'


describe("Hashtable without values", function()
	local StringHashSet = HT.HashTable(rawstring)

	it("should insert and check the existence of values", terra()
		var hash_set = O.new(StringHashSet)

		var expected = {"STRONK", "Identity"}

		hash_set.insert(expected._1)
		hash_set.insert(expected._2)

		hash_set.debug_full_repr()

		assert.is_true(hash_set.has(expected._1))
		assert.is_true(hash_set.has(expected._2))
	end)
end)

describe("Implementation.DenseHashTable HashMap", function()
end)
