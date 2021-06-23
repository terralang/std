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
		metadata: &uint8
		-- The backing array of the hashtable.
		buckets: &KeyType
	}

	local struct HashResult {
		bucket_index: uint
		h1: uint
		h2: uint8
	}

	-- Allocates memory large enough to fit the provided number of groups and associated metadata.
	-- Returns a pointer to the metadata array and a pointer to the bucket array.
	local terra malloc_by_groups(groups: uint): tuple(&uint8, &KeyType)
		var buckets = groups * GroupLength
		var big_ol_chunk_of_memory = [ Alloc ]:alloc_raw(buckets + (sizeof([KeyType]) * buckets))
		return { [&uint8] (big_ol_chunk_of_memory), [&KeyType] ([&uint8] big_ol_chunk_of_memory + GroupLength) }
	end

	-- Initalizes the metadata array with MetadataEmpty
	local terra initalize_metadata(metadata_array: &uint8, length: uint)
		for i = 0, self.length do
			metadata_array[i] = MetadataEmpty
		end
	end

	local terra compute_hashes(capacity: uint, key: KeyType): HashResult
		var hash = [ HashFn ](key)

		return HashResult {
			bucket_index = (hash >> 7) % capacity,
			h1 = hash >> 7,
			h2 = hash and MetadataHashBitmap
		}
	end

	--[[ 
		Probes the table for the bucket that would contain the key. Capacity should be a power of 2.
		
		Returns an index which is only valid for the current state of the table. 
		This index may point to a bucket which contains the key, or an empty bucket where the key should be inserted if the key does not exist.
		The return value is negative if an error occured.
	]]--
	local terra probe_clever(hash_result: HashResult, metadata_array: &uint8, capacity: uint): int
		for j = hash_result.bucket_index, capacity + hash_result.bucket_index do
			i = j and (capacity - 1)
			var m = metadata_array[i]

			if m == MetadataEmpty or m == hash_result.h2 then
				return i
			end
		end

		return -1
	end

	-- Resizes the hashtable by doubling the number of groups.
	local terra resize_hashtable(hashtable: Hashtable)
		var old_group_count = hashtable.capacity / GroupLength
		var new_group_count = old_group_count * 2
		var new_capacity = new_group_count * GroupLength

		-- Not using realloc because we need rehash everything.
		-- That's going to be really hard within the same memory segment
		var new_metadata, new_buckets = malloc_by_groups(new_group_count)

		initalize_metadata(new_memory_chunk, new_capacity)

		-- Iterate through the old hashtable and rehash
		for i = 0, hashtable.capacity do
			if hashtable.metadata[i] != MetadataEmpty then
				var key = hashtable.buckets[i]
				var hash_result = compute_hashes(new_capacity, key)
				var probe_index = probe_clever(hash_result, new_metadata, new_capacity)

				new_metadata[probe_index] = hash_result.h2
				new_buckets[probe_index] = key
			end
		end

		-- Free old memory
		[ Alloc ]:free_raw(new_metadata)

		hashtable.capacity = new_capacity
		hashtable.metadata = new_metadata
		hashtable.buckets = new_buckets
	end

	terra Hashtable:init()
		var metadata, buckets = malloc_by_groups(1)
		
		self:_init {
			capacity = GroupLength,
			size = 0,
			metadata = metadata,
			buckets = buckets
		}

		initalize_metadata(self.metadata, self.capacity)
	end

	terra Hashtable:insert(key: KeyType)
		if self.size == self.capacity then
			resize_hashtable(self)
		end

		var hash_result = compute_hashes(self.capacity, key)
		var probe_index = probe_clever(hash_result, self.metadata, self.capacity)

		self.size = self.size + 1
		self.metadata[probe_index] = hash_result.h2
		self.buckets[probe_index] = key
	end

	return Hashtable
end

return HashTable
