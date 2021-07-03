local O = require 'std.object'
local HT = require 'std.hashtable'
local CIO = terralib.includec("stdio.h")
local CStr = terralib.includec("string.h")
local Alloc = require 'std.alloc'

describe("Implementation.DenseHashTable", function()
	local StringHashSet = HT.Implementation.DenseHashTable(rawstring, nil, HT.CreateDefaultHashFunction(rawstring), HT.CreateDefaultEqualityFunction(rawstring), Alloc.default_allocator)

	local StringHashMap = HT.Implementation.DenseHashTable(rawstring, rawstring, HT.CreateDefaultHashFunction(rawstring), HT.CreateDefaultHashFunction(rawstring), Alloc.default_allocator)

	it("hash set form should satisfy the CTHashTable constraint", function()
		HT.CTHashTable(StringHashSet)
	end)

	if("hash map form should satisfy the CTHashTable constraint", function()
		HT.CTHashTable(StringHashMap)
	end)
end)
