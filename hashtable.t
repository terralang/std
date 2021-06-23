local A = require 'std.alloc'
local O = require 'std.object' 

local CStr = terralib.includec("string.h")

--[[ Factory function for default hash functions of various types. Generally, the hashing functions outputted are implementation of djb2. ]]--
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
function HashTable(KeyType, HashFn, Alloc)
	HashFn = HashFn or CreateDefaultHashFunction(KeyType)
	Alloc = Alloc or A.default_allocator

	local GroupLength = constant(uint, 16)

	local MetadataHashBitmap = constant(uint8, 127) -- 0b01111111
	local MetadataEmpty = constant(uint8, 128) -- 0b10000000

	local struct Hashtable(O.Object) {
		-- The total number of buckets in the table.
		capacity: uint
		-- The number of items stored in the table
		size: uint
		-- Array of bytes holding the metadata of the table.
		metadata: &int8
		-- The backing array of the hashtable.
		buckets: &KeyType
	}

	local struct HashResult {
		bucket_index: uint
		h1: uint
		h2: uint8
	}

	-- Allocates memory large enough to fit the provided number of groups and associated metadata. Returns a pointer to this block of memory.
	local terra malloc_by_groups(groups: uint): &opaque
		var buckets = groups * GroupLength
		return [ Alloc ]:alloc_raw(buckets + (sizeof([KeyType]) * buckets))
	end

	local terra compute_hashes(capacity: uint, key: KeyType): HashResult
		var hash = [ HashFn ](key)

		return HashResult {
			bucket_index = (hash >> 7) % capacity,
			h1 = hash >> 7,
			h2 = hash and MetadataHashBitmap
		}
	end

	terra Hashtable:init()
		var big_ol_chunk_of_memory = malloc_by_groups(1)
		
		self:_init {
			capacity = GroupLength,
			size = 0,
			metadata = [&int8] (big_ol_chunk_of_memory),
			buckets =  [&KeyType] ( [&int8] (big_ol_chunk_of_memory) + GroupLength)
		}

		-- Initialize the metadata array
		for i = 0, self.capacity do
			self.metadata[i] = MetadataEmpty
		end
	end

	terra Hashtable:insert(key: KeyType)
		var hash_result = compute_hashes(self.capacity, key)

		self.size = self.size + 1
		self.metadata[hash_result.bucket_index] = hash_result.h2
		self.buckets[hash_result.bucket_index] = key
	end

	return Hashtable
end

return HashTable
