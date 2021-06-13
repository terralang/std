local A = require 'std.alloc'
local O = require 'std.object' 

local CStr = terralib.includec("string.h")

--[[ Factory function for default hash functions of various types. Generally, the hasing functions outputted are implementation of djb2. ]]--
function CreateDefaultHashFunction(KeyType)
	local function ComputeSize(keyValue)
		if KeyType == rawstring then
			return `CStr.strlen(keyValue)
		else
			return `sizeof([KeyType])
		end
	end

	local terra hash_function(data: KeyType): uint
		var hash: uint = 5381

		for i = 0, [ComputeSize(data)] do
			hash = ((hash << 5) + hash * 33) + data[i]
		end

		return hash
	end

	return hash_function
end

--[[ 
	Creates a new HashTable type.

	This hashtable is based on the dense_hash_set implementation by Google.
--]]
function HashTable(Key, HashFn, GroupLength, Alloc)
	HashFn = HashFn or CreateDefaultHashFunction(Key)
	GroupLength = GroupLength or 48
	Alloc = Alloc or A.default_allocator

	local struct Entry {
		-- A pointer to the metadata byte.
		metadata: &int8

		-- A pointer to the bucket.
		bucket: &Key
	}

	local struct Hashtable(O.Object) {
		-- The total number of buckets in the table.
		capacity: uint
		-- Array of bytes holding the metadata of the table.
		metadata: &int8
		-- The backing array of the hashtable.
		buckets: &Key
	}

	-- Allocates memory large enough to fit the provided number of groups and associated metadata. Returns a pointer to this block of memory.
	local terra malloc_by_groups(groups: uint): &opaque
		var buckets = groups * [ GroupLength ]
		return [ Alloc ]:alloc_raw(buckets + (sizeof([Key]) * buckets))
	end

	terra Hashtable:init()
		var big_ol_chunk_of_memory = malloc_by_groups(1)
		
		self:_init {
			capacity = [ GroupLength ],
			metadata = [&int8] (big_ol_chunk_of_memory),
			buckets =  [&Key] ( [&int8] (big_ol_chunk_of_memory) + [ GroupLength ])
		}
	end

	terra Hashtable:insert(key: Key)
		var hash = [ HashFn ](key)
	end

	return Hashtable
end

return HashTable
