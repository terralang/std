local A = require 'std.alloc'
local O = require 'std.object'
local CT = require 'std.constraint'

local CStr = terralib.includec("string.h")
local Cstdio = terralib.includec("stdio.h")

local M = {}

-- Defines a low-level generic HashTable interface.
-- capacity = A field with an integer type that defines the capacity of the container.
-- size = A field with an integer type that defines the number of items in the contianer. Should always be less than or equal to capacity.
-- resize = A method that expands the capacity of the container. Returns 0 on success.
-- lookup_handle = A method that takes its a key and it's hash and returns a handle which refers to a location in the container that can be used for storage or retrevial.
-- store_handle = A method which takes a key (and a value if its a key/value store), and a Handle, and stores the item at the location. Returns 0 on success.
-- retrieve_handle = A method that takes a handle and returns the key or key and value at the location. May return null on failure.
M.CTHashTable = CT.All(
	CT.Field("capacity", CT.Integral),
	CT.Field("size", CT.Integral),
	CT.Method("resize", nil, CT.Integral),
	CT.MetaConstraint(
		function(KeyType, ValueType, HandleType)
			local lookup_constraint = CT.Method("lookup_handle", CT.Type(KeyType), CT.Type(HandleType)),
			
			if ValueType ~= nil then
				local store_constraint = CT.Method("store_handle", {CT.Type(HandleType), CT.Type(KeyType), CT.Type(ValueType)}, CT.Integral)
				local retreive_constraint = CT.Method("retrieve_handle", CT.Type(HandleType), {CT.Type(KeyType), CT.Type(ValueType)})
			else
				local store_constraint = CT.Method("store_handle", {CT.Type(HandleType), CT.Type(KeyType)}, CT.Integral)
				local retreive_constraint = CT.Method("retrieve_handle", CT.Type(HandleType), CT.Type(KeyType))
			end

			return CT.All(lookup_constraint, insert_constraint, retrieve_handle)
		end,
		CT.TerraType, CT.TerraType, CT.TerraType
	)
)

M.Implementation = {}

function M.Implementation.DenseHashTable(KeyType, ValueType, HashFn, EqFn, Alloc)
	MetadataHashBitmap = constant(uint8, 127) -- 0b01111111
	MetadataEmpty = constant(uint8, 128) -- 0b10000000
	GroupLength = constant(uint, 16)

	if ValueType == nil then
		local BucketType = KeyType
		local IsKeyEq = macro(function(key, bucket)
			return `EqFn(key, bucket)
		end)
	else
		local BucketType = struct {
			key: KeyType
			value: ValueType
		}
		local IsKeyEq = macro(function(key, bucket)
			return `EqFn(key, bucket.value)
		end)
	end

	-- Allocates and initalizes memory for the hashtable. The metadata array is initalized to `MetadataEmpty`. Buckets are not initialized to any value.
	-- Returns a quadruple: The first value is success, the second value is an opaque pointer which should be passed to `free`, the third value is the metadata array, and the forth value is the bucket array.
	-- Note that if success is false, then all other values are null.
	local terra table_calloc(capacity: uint): tuple(bool, &opaque, &uint8, &BucketType)
		var opaque_ptr = Alloc:alloc_raw(capacity * (sizeof(BucketType) + 1))
		
		if opaque_ptr == nil then
			return {false, nil, nil, nil}
		end

		var metadata_array = [&uint8](opaque_ptr)
		var buckets_array = [&BucketType](metadata_array + capacity)

		CStr.memset(metadata_array, MetadataEmpty, capacity)

		return {true, opaque_ptr, metadata_array, buckets_array}
	end

	local struct HashResult {
		initial_bucket_index: uint
		h1: uint
		h2: uint8
	}

	local struct BucketHandle {
		iserror: bool
		index: uint
		hash_result: HashResult
	}

	local terra compute_hash(key: KeyType, capacity: uint): HashResult
		var hash = [ HashFn ](key)

		return SM.HashResult {
			initial_bucket_index = (hash >> 7) % capacity,
			h1 = hash >> 7,
			h2 = hash and SM.MetadataHashBitmap
		}
	end

	struct DenseHashTable(O.Object) {
		-- The total number of buckets in the table.
		capacity: uint
		-- The number of items stored in the table
		size: uint
		-- Pointer to free on destruction
		opaque_ptr: &opaque
		-- Array of bytes holding the metadata of the table.
		metadata: &uint8
		-- The backing array of the hashtable.
		buckets: &BucketType
	}

	-- Assigns all the fields of the hashtable to the specified values.
	-- This is done because I'm not sure if I can reuse "self:_init" and we need saftey when mangling the internals in resize.
	terra reassign_internals(htable: DenseHashTable, capacity: uint, size: uint, opaque_ptr: &opaque, metadata: &uint8, buckets: &BucketType)
		htable.capacity = capacity
		htable.size = size
		htable.opaque_ptr = opaque_ptr
		htable.metadata = metadata
		htable.buckets = buckets
	end

	terra DenseHashTable:init()
		var alloc_success, opaque_ptr, metadata, buckets = table_calloc(initial_capacity)

		self:_init {
			capacity = GroupLength,
			size = 0,
			opaque_ptr = opaque_ptr,
			metadata = metadata,
			buckets = buckets,
			entries = nil
		}
	end

	terra DenseHashTable:destruct()
		if self.opaque_ptr ~= nil then
			[Alloc]:free_raw(self.opaque_ptr)
		end

		CStr.memset(self, 0, sizeof(SM.HashTable)
	end

	terra DenseHashTable:lookup_handle(key: KeyType): BucketHandle 
		var hash_result = compute_hash(key, self.capacity)
		var virtual_limit = self.capacity + hash_result.initial_bucket_index

		for virtual_index = hash_result.initial_bucket_index, virtual_limit do
			var index = virtual_index and (capacity - 1)
			var metadata = self.metadata[index]

			if metadata == SM.MetadataEmpty or (metadata == hash_result.h2 and IsKeyEq(key, self.buckets[index])) then
				return BucketHandle {false, index, hash_result}
			end
		end

		return BucketHandle {true, -1, nil}
	end

	local StoreHandleBody = macro(function(self, handle, key, value) 
		return quote
			if [handle].iserror then
				return [handle].index
			end

			var index = [handle].index
			var hash_result = [handle].hash_result
			var previous_metadata = self.metadata[index]	

			[self].metadata[index] = hash_result.h2
			[self].buckets[index] = escape
				if ValueType ~= nil then
					emit(`BucketType { key = [key], value = [value])
				else
					emit(`key)
				end
			end

			if previous_metadata == MetadataEmpty then
				[self].size = [self].size + 1
			end

			return 0
		end
	end)

	if ValueType ~= nil then
		terra DenseHashTable:store_handle(handle: BucketHandle, key: KeyType, value: ValueType): int
			StoreHandleBody(self, handle, key, value)
		end

		terra DenseHashTable:retrieve_handle(handle: BucketHandle): tuple(KeyType, ValueType)
			if handle.iserror then
				return nil
			end
			
			var bucket = self.buckets[handle.index]
			return { bucket.key, bucket.value }
		end
	else
		terra DenseHashTable:store_handle(handle: BucketHandle, key: KeyType): int
			StoreHandleBody(self, handle, key)
		end

		terra DenseHashTable:retrieve_handle(handle: BucketHandle): KeyType
			if handle.iserror then
				return nil
			end

			return self.buckets[handle.index]
		end
	end

	terra DenseHashTable:resize(): int
		var old_size = self.size
		var old_capacity = self.capacity
		var old_opaque_ptr = self.opaque_ptr
		var old_metadata = self.metadata
		var old_buckets = self.buckets

		var new_capacity = self.capacity * 2
		var alloc_success, new_opaque_ptr, new_metadata, new_buckets = table_calloc(new_capacity)

		if ~alloc_success then
			return -1
		end

		reassign_internals(self, new_capacity, 0, new_opaque_ptr, new_metadata, new_buckets)

		for i = 0, old_capacity do
			if metadata[i] ~= MetadataEmpty then
				var old_bucket: BucketType = self.old_buckets[i]
				escape
					if ValueType ~= nil then
						emit(quote
							var handle = self:lookup_handle(old_bucket.key)
							var result = self:store_handle(handle, old_bucket.key, old_bucket.value)
						end)
					else
						emit(quote
							var handle = self.lookup_handle(old_bucket)
							var result = self:store_handle(handle, old_bucket)
						end)
					end
				end

				if result != 0 then
					-- An error occured when rehashing. Reset the state of the hashtable and return an error.
					reassign_internals(self, old_capacity, old_size, old_opaque_ptr, old_metadata, old_buckets)
					[Alloc]:free(new_opaque_ptr)
					return 1
				end
			end
		end

		-- Free old data
		[Alloc]:free(old_opaque_ptr)

		return 0
	end

	-- Prints a debug view of the metadata array to stdout
	terra DenseHashTable:_debug_metadata_repr()
		Cstdio.printf("HashTable Size: %u, Capacity: %u, OpaquePtr: %p\n", self.size, self.capacity, self.opaque_ptr)
		for i = 0, self.capacity do
			Cstdio.printf("[%u]\t%p - 0x%02X\n", i, self.metadata + i, self.metadata[i])
		end
	end

	-- Prints a debug view of the table to stdout.
	terra SM.HashTable:debug_full_repr()
		Cstdio.printf("HashTable Size: %u, Capacity: %u, OpaquePtr: %p\n", self.size, self.capacity, self.opaque_ptr)
		for i = 0, self.capacity do
			Cstdio.printf("[%u]\tMetadata: %p = 0x%02X\tBucket: %p = ", i, self.metadata + i, self.metadata[i], self.buckets + i)

			if self.metadata[i] == 128 then
				Cstdio.printf("Empty\n", self.buckets + i)
			elseif self.buckets + i == nil then
				Cstdio.printf("NULLPTR\n")
			else
				-- TODO: this won't work all the time, refactor to handle all types later
				Cstdio.printf("%s\n", self.buckets[i])
			end
		end
	end
end

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
		local terra default_string_hash(str: KeyType)
			return M.hash_djb2(str, CStr.strlen(str))
		end
		return default_string_hash
	-- TODO: Add more cases here
	else
		local terra naive_hash(obj: KeyType)
			return M.hash_djb2(obj, sizeof(obj))
		end
		return naive_hash
	end
end

function M.CreateDefaultEqualityFunction(KeyType)
	-- TODO: Need more cases here too
	local terra naive_equal_function(k1: KeyType, k2: KeyType): bool
		return k1 == k2
	end
	return naive_equal_function
end

return M
