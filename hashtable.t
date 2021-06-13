local A = require 'std.alloc'
local O = require 'std.object' 
local M = {}

--[[ 
	Creates a new HashTable type.

	This hashtable is based on the dense_hash_set implementation by Google.
--]]
function M.HashTable(Key, GroupLength, Alloc)
	GroupLength = GroupLength or 48
	Alloc = Alloc or A.default_allocator

	local struct Entry {
		value: &Key
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
		buckets = groups * [ GroupLength ]
		return [ Alloc ].alloc(groups + (sizeof([Key]) * buckets))
	end

	terra Hashtable:init()
		var big_ol_chunk_of_memory = malloc_by_groups(1)
		
		self:_init {
			capacity = [ GroupLength ],
			metadata = big_ol_chunk_of_memory,
			buckets = big_ol_chunk_of_memory[ [GroupLength] ]
		}
	end

	return HashTable
end

return M
