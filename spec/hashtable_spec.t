local HT = require 'std.hashtable'
local O = require 'std.object'
local A = require 'std.alloc'

local Cio = terralib.includec("stdio.h")

describe("HashTable without values", function()
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

		var rm_result = hash_set:remove("I'm filled")
		assert.is_true(rm_result:is_ok()) -- Removal should return an ok with the removed object
		assert.equal("I'm filled", rm_result.ok.key) -- Returned object should be the correct one

		assert.equal(2, hash_set.size) -- Size should decrease by one
		assert.is_false(hash_set:has("I'm filled")) -- :has() should not report the object as existing

		-- Should return an error
		assert.equal(HT.Errors.NotFound, hash_set:remove("doesn't exist").err)
		assert.equal(2, hash_set.size)

		hash_set:destruct()
	end)

	it("should clean the table when rehashing", terra()
		var hash_set: StringHashSet
		hash_set:init()

		hash_set:insert("Somewhere in Stockholm")
		hash_set:insert("Broken Arrows")
		hash_set:insert("City Lights")

		hash_set:remove("Broken Arrows")
		hash_set:reserve(31)

		hash_set:debug_full_repr()

		hash_set:destruct()
	end)

	it("should properly keep track of hash-collided entries", function()
		local terra bad_hash_function(key: rawstring): uint
			return 1
		end

		local BadStringHashSet = HT.HashTable(rawstring, nil, bad_hash_function) 

		local terra test()
			var hash_set: BadStringHashSet
			hash_set:init()

			hash_set:insert("1")
			hash_set:insert("2")
			hash_set:insert("3")
		
			assert.is_true(hash_set:remove("1"):is_ok())
			assert.is_true(hash_set:remove("2"):is_ok())
			assert.is_true(hash_set:remove("3"):is_ok())

			hash_set:destruct()
		end

		test()
	end)

	it("should create Entry objects for items that exist", terra()
		var hash_set: StringHashSet
		hash_set:init()
		hash_set:insert("sharks")

		var actual = hash_set:entry("sharks").ok
		assert.is_false(actual:is_empty())
		assert.equal("sharks", actual:key())

		hash_set:destruct()
	end)

	it("should create Entry objects for items that don't exist", terra()
		var hash_set: StringHashSet
		hash_set:init()

		var actual = hash_set:entry("shark").ok
		assert.is_true(actual:is_empty())

		hash_set:destruct()
	end)
end)

describe("HashTable with values", function()
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

	it("should resize its capacity without changing items", terra()
		var hash_map: StringHashMap
		hash_map:init()

		hash_map:insert("1", "Drink Water")
		hash_map:insert("2", "Eat food")
		hash_map:insert("3", "Breathe air")

		assert.equal(3, hash_map.size)
		assert.equal(0, hash_map:reserve(31))
		assert.is_true(hash_map.capacity >= 31)

		assert.is_true(hash_map:has("1"))
		assert.is_true(hash_map:has("2"))
		assert.is_true(hash_map:has("3"))

		hash_map:destruct()
	end)

	it("should be able to remove items by keys", terra()
		var hash_map: StringHashMap
		hash_map:init()

		hash_map:insert("Super Dream World", "Kobaryo")
		hash_map:insert("Does anyone actually", "read these things? lol")
		hash_map:insert("I feel like tests", "are vastly underappreciated in software engineering.")
		hash_map:insert("a", "b")
		hash_map:insert("c", "d")
		hash_map:insert("e", "f")

		assert.equal(6, hash_map.size)

		var remove_result = hash_map:remove("Super Dream World")
		assert.is_true(remove_result:is_ok())
		assert.equal(5, hash_map.size)
		assert.equal("Super Dream World", remove_result.ok.key)
		assert.equal("Kobaryo", remove_result.ok.value)
		assert.is_false(hash_map:has("Super Dream World"))

		remove_result = hash_map:remove("404 not found")
		assert.is_true(remove_result:is_err())
		assert.equal(5, hash_map.size)
		assert.equal(HT.Errors.NotFound, remove_result.err)

		hash_map:destruct()
	end)

	it("should properly keep track of hash-collided entries", function()
		local terra bad_hash_function(key: rawstring): uint
			return 1
		end

		local BadStringHashMap = HT.HashTable(rawstring, rawstring, bad_hash_function) 

		local terra test()
			var hash_map: BadStringHashMap
			hash_map:init()

			hash_map:insert("1", "ttt")
			hash_map:insert("2", "ddd")
			hash_map:insert("3", "fff")

			assert.is_true(hash_map:remove("1"):is_ok())
			assert.is_true(hash_map:remove("2"):is_ok())
			assert.is_true(hash_map:remove("3"):is_ok())

			hash_map:destruct()
		end

		test()
	end)

	it("should create Entry objects for items that exist", terra()
		var hash_map: StringHashMap
		hash_map:init()
		hash_map:insert("shark girls", "are good")

		var actual = hash_map:entry("shark girls").ok
		assert.is_false(actual:is_empty())
		assert.equal("shark girls", actual:key())
		assert.equal("are good", actual:value().ok)

		hash_map:destruct()
	end)

	it("should create Entry objects for items that don't exist", terra()
		var hash_map: StringHashMap
		hash_map:init()

		var actual = hash_map:entry("shark girls").ok
		assert.is_true(actual:is_empty())

		hash_map:destruct()
	end)
end)

describe("Entry on HashTable without value", function()
	local StringHashSet = HT.HashTable(rawstring)

	it("should insert the value if it doesn't exist", terra()
		var hash_set: StringHashSet
		hash_set:init()

		var sut = hash_set:entry("sharks").ok
		assert.is_true(sut:is_empty())
		assert.equal("sharks", sut:or_insert())
		assert.is_true(hash_set:has("sharks"))

		hash_set:destruct()
	end)
end)

describe("Entry on HashTable with value", function()
	local StringHashMap = HT.HashTable(rawstring, rawstring)

	it("should insert a value if the value doesn't exist", terra()
		var hash_map: StringHashMap
		hash_map:init()

		var sut = hash_map:entry("dark cat").ok
		assert.is_true(sut:is_empty())
		assert.equal("crazy milk", sut:or_insert("crazy milk"))
		
		assert.is_false(sut:is_empty())
		assert.is_true(hash_map:has("dark cat"))
		assert.equal("crazy milk", hash_map:get("dark cat").ok)

		hash_map:destruct()
	end)

	it("should return the existing value if the value exists", terra()
		var hash_map: StringHashMap
		hash_map:init()
		hash_map:insert("Porter Robinson", "Look at the Sky")
		
		var sut = hash_map:entry("Porter Robinson").ok
		var actual = sut:or_insert("Musician")

		assert.equal("Look at the Sky", actual)
		assert.equal("Look at the Sky", hash_map:get("Porter Robinson").ok)

		hash_map:destruct()
	end)
end)
