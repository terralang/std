local A = require 'std.alloc'
local O = require 'std.object' 

local CStr = terralib.includec("string.h")

local M = {}

-- Implementation of djb2. Treats all data as a stream of bytes.
terra M.hash_djb2(data: &int8, size: uint): uint
	var hash: uint = 5381

	for i = 0, size do
		hash = ((hash << 5) + hash * 33) + data[i]
	end

	return hash
end

function M.CreateDefaultHashFunction(KeyType)
	if KeyType == rawstring then
		return local terra default_string_hash(str: KeyType)
			return M.hash_djb2(str, CStr.strlen(str))
		end
	-- TODO: Add more cases here
	else
		return local terra naive_hash(obj: KeyType)
			return M.hash_djb2(obj, sizeof(obj))
		end
	end
end

function M.CreateDefaultEqualityFunction(KeyType)
	-- TODO: Need more cases here too
	local terra naive_equal_function(1: KeyType, k2: KeyType): bool
		return k1 == k2
	end
	return equal_function
end

function M.CreateHashTableSubModule(KeyType, HashFn, EqFn, Alloc)
	HashFn = HashFn or M.CreateDefaultHashFunction(KeyType)
	EqFn = EqFn or M.CreateDefaultEqualityFunction(KeyType)
	Alloc = Alloc or A.default_allocator

	local SM = {}

	SM.MetadataHashBitmap = constant(uint8, 127) -- 0b01111111
	SM.MetadataEmpty = constant(uint8, 128) -- 0b10000000
	SM.GroupLength = constant(uint, 16)


	-- Produces a collection of methods used for the HashTable implementation.
	-- This is considered to be an implementation detail and subject to API changes. The only reason this is exposed is for automated testing purposes.
	SM._Plumbing = {}

	-- Allocates and initalizes memory for the hashtable. The metadata array is initalized to `MetadataEmpty`. Buckets are not initialized to any value.
	-- Returns a quadruple: The first value is success, the second value is an opaque pointer which should be passed to `free`, the third value is the metadata array, and the forth value is the bucket array.
	-- Note that if success is false, then all other values are null.
	terra SM._Plumbing.table_calloc(capacity: uint): tuple(bool, &opaque, &uint8, &KeyType)
		var opaque_ptr = Alloc:alloc_raw(capacity * (sizeof(KeyType) + 1))
		
		if opaque_ptr == nil then
			return {false, nil, nil, nil}
		end

		var metadata_array = [&int8](opaque_ptr)
		var buckets_array = [&KeyType](metadata_array + capacity)

		CStr.memset(metadata_array, SM.MetadataEmpty, capacity)

		return {true, opaque_ptr, metadata_array, buckets_array}
	end
		if KeyType == rawstring then
			return terra default_string_hash(str: KeyType)
				return M._Plumbing.hash_djb2(str, CStr.strlen(str))
			end
		end
	end

	struct SM._Plumbing.HashResult {
		initial_bucket_index: uint
		h1: uint
		h2: uint8
	}

	terra SM._Plumbing.compute_hashes(key: KeyType, capacity: uint): SM._Plumbing.HashResult
		var hash = [ HashFn ](key)

		return HashResult {
			initial_bucket_index = (hash >> 7) % capacity,
			h1 = hash >> 7,
			h2 = hash and SM.MetadataHashBitmap
		}
	end

	-- Probes the table for the bucket that would contain the key.
	-- Expects that capacity is a power of 2.
	-- Returns an index which is only valid for the current state of the table. The index may point to a bucket which contains an existing key, 
	-- or to an empty bucket where the key should be inserted if the key does not exist.
	-- The return value is negative if no bucket can be found.
	terra SM._Plumbing.probe(key: KeyType,
							 hash_result: SM._Plumbing.HashResult,
							 metadata_array: &uint8,
							 buckets: &KeyType,
							 capacity: uint): int
		for virtual_index = hash_result.initial_bucket_index, capacity + hash_result.initial_bucket_index do
			var index = virtual_index and (capacity -1)
			var metadata = metadata_array[i]

			if m == SM.MetadataEmpty or (m == hash_result.h2 and [EqFn](key, buckets[i])) then
				return i
			end
		end

		return -1
	end

	SM._Plumbing.probe_table = macro(function(hash_table, key, hash_result)
		return `SM._Plumbing.probe(key, hash_result, hash_table.metadata, hash_table.buckets, hash_table.capacity)
	end)

	-- Inserts a key into buckets and sets appropriate metadata.
	-- The reason this is a plumbing function instead of public api is because rehash needs to perform insertions.
	terra SM._Plumbing.insert(key: KeyType, metadata_array: &uint8, buckets: &KeyType, capacity: uint)
		var hash_result = SM._Plumbing.compute_hashes(key, capacity)
		var index = SM._Plumbing.probe(key, hash_result, metadata_array, buckets, capacity)

		metadata_array[index] = hash_result.h2
		buckets[index] = key
	end

	terra SM._Plumbing.rehash_table(old_metadata: &uint8,
									old_buckets: &KeyType,
									old_capacity: uint,
									new_metadata: &uint8,
									new_buckets: &KeyType,
									new_capacity: uint)
		for i = 0, old_capacity do
			if old_metadata[i] ~= SM.MetadataEmpty then
				var key = old_buckets[key]
				SM._Plumbing.insert(key, new_metadata, new_buckets, new_capacity)
			end
		end
	end

	-- Resizes the hashtable.
	-- Returns true on success, false otherwise.
	terra SM._Plumbing.resize_hashtable(hashtable: &SM.HashTable): bool
		var new_capacity = hashtable.capacity * 2
		var alloc_success, opaque_ptr, new_metadata, new_buckets = SM._Plumbing.table_calloc(new_capacity)

		if alloc_success == false then
			return false

		SM._Plumbing.rehash_table(hashtable.metadata, hashtable.buckets, hashtable.capacity, new_metadata, new_buckets, new_capacity)

		[Alloc]:free_raw(hashtable.opaque_ptr)
		hashtable.opaque_ptr = opaque_ptr
		hashtable.metadata = new_metadata
		hashtable.buckets = new_buckets
	end
	
	struct SM.HashTable(O.Object) {
		-- The total number of buckets in the table.
		capacity: uint
		-- The number of items stored in the table
		size: uint
		-- Pointer to free on destruction
		opaque_ptr: &opaque
		-- Array of bytes holding the metadata of the table.
		metadata: &uint8
		-- The backing array of the hashtable.
		buckets: &KeyType
	}

	terra SM.HashTable:init()
		var alloc_success, opaque_ptr, metadata, buckets = table_calloc(1)
		
		self:_init {
			capacity = GroupLength,
			size = 0,
			opaque_ptr = opaque_ptr,
			metadata = metadata,
			buckets = buckets
		}
	end

	terra SM.HashTable:destruct()
		[Alloc]:free_raw(self.opaque_ptr)
		self.opaque_ptr = nil
		self.metadata = nil
		self.buckets = nil
	end

	terra SM.HashTable:insert(key: KeyType)
		if self.size == self.capacity then
			resize_hashtable(self)
		end

		SM._Plumbing.insert(key, self.metadata_array, self.buckets, self.capacity)
		self.size = self.size + 1
	end

	terra SM.HashTable:has(key: KeyType): bool
		var hash_result = compute_hashes(key, self.capacity)
		var probe_index = SM._Plumbing.probe_tabe(self, key, hash_result)

		if probe_index == -1 or self.metadata[probe_index] == MetadataEmpty then
			return false
		end

		return true
	end

	return SM
end

-- Convienience function that returns a HashTable struct type.
function M.HashTable(KeyType, HashFn, EqFn, Alloc)
	local SM = M.CreateHashTableSubModule(KeyType, HashFn, EqFn, Alloc)
	return SM.HashTable
end

return M
