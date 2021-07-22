local HT = require 'std.hashtable'
local O = require 'std.object'

local Cio = terralib.includec("stdio.h")

describe("Hashtable without values", function()
	local StringHashSet = HT.HashTable(rawstring)

	it("should insert and check the existence of values", terra()
		var hash_set = O.new(StringHashSet)

		var expected = {"STRONK", "Identity"}

		assert.equal(0, hash_set:insert(expected._0))
		assert.equal(0, hash_set:insert(expected._1))

		assert.is_true(hash_set:has(expected._0))
		assert.is_true(hash_set:has(expected._1))
		assert.equal(2, hash_set.size)
	end)

	
	it("should resize its capacity without changing items", terra()
		var hash_set: StringHashSet
		hash_set:init()

		hash_set:insert("Cutiemarks")
		hash_set:insert("and the")
		hash_set:insert("things that")
		hash_set:insert("bind us")


		assert.equal(0, hash_set:reserve(31))
		assert.equal(4, hash_set.size)
		assert.is_true(hash_set.capacity >= 31)

		hash_set:destruct()
	end)

	it("should be able to remove keys", terra()
		var hash_set: StringHashSet
		hash_set:init()

		hash_set:insert("I'm filled")
		hash_set:insert("with")
		hash_set:insert("wanderlust")

		-- Should remove the item and return it.
		assert.equal(3, hash_set.size)
		assert.equal("I'm filled", hash_set:remove("I'm filled").ok.key)
		assert.equal(2, hash_set.size)

		-- Should return an error
		assert.equal(HT.Errors.NotFound, hash_set:remove("doesn't exist").err)
		assert.equal(2, hash_set.size)

		hash_set:destruct()
	end)
end)

describe("Implementation.DenseHashTable HashMap", function()
	local StringHashMap = HT.HashTable(rawstring, rawstring)

	it("should insert and check the existence of values", terra()
		var hash_map = O.new(StringHashMap)

		assert.equal(0, hash_map:insert("I'm living proof", "that the worst can be beat"))
		assert.equal(0, hash_map:insert("if ya pull yourself together", "you can get on your feet"))
		assert.equal(0, hash_map:insert("living proof that", "the strength you will need"))
		assert.equal(0, hash_map:insert("has been in you forever", "but to get it, you'll bleed"))

		assert.is_true(hash_map:has("I'm living proof"))
		assert.is_true(hash_map:has("if ya pull yourself together"))
		assert.is_true(hash_map:has("living proof that"))
		assert.is_true(hash_map:has("has been in you forever"))
		assert.equal(4, hash_map.size)
	end)

	it("should be able to remove items by keys", terra()
		var hash_map: StringHashMap
		hash_map:init()

		hash_map:insert("Super Dream World", "Kobaryo")
		hash_map:insert("Does anyone actually", "read these things? lol")
		hash_map:insert("I feel like tests", "are vastly underappreciated in software engineering.")
		hash_map:insert("I don't have a choice", "I have to write extensive tests to save me from myself.")
		hash_map:insert("The only way I can catch", "silly logic and syntax mistakes are with tests.")
		hash_map:insert("they say that everyone makes", "these mistakes but idk.")

		assert.equal(6, hash_map.size)

		var remove_result = hash_map:remove("Super Dream World")
		assert.is_true(remove_result:is_ok())
		assert.equal(5, hash_map.size)
		assert.equal("Super Dream World", remove_result.ok.key)
		assert.equal("Kobaryo", remove_result.ok.value)

		remove_result = hash_map:remove("404 not found")
		assert.is_true(remove_result:is_err())
		assert.equal(5, hash_map.size)
		assert.equal(HT.Errors.NotFound, remove_result.err)

		hash_map:destruct()
	end)
end)
