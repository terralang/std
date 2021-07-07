local A = require 'std.alloc'
local O = require 'std.object'
local CT = require 'std.constraint'
local R = require 'std.result'

local CStr = terralib.includec("string.h")
local Cstdio = terralib.includec("stdio.h")

local M = {}

M.Implementation = {}

function M.Implementation.BucketType(KeyType, ValueType)
	local BucketType = (ValueType ~= nil) and
		{ TerraType = struct { key: KeyType value: ValueType }, Tag = "StructType" } or
		{ TerraType = KeyType, Tag = "KeyType" }
	
	function BucketType:Choose(S, K)
		if self.Tag == "StructType" then
			return S
		else
			return K
		end
	end

	function BucketType:ChooseLazy(SFn, KFn)
		return self:Choose(SFn, KFn)()
	end

	-- Calls either matchA or matchB with value as a parameter depending on what the type is.
	function BucketType:Match(value, S, K)
		return self:Choose(S, K)(value)
	end

	function BucketType:CreateBucket(key, value)
		return self:ChooseLazy(function() return `[self.TerraType] {[key], [value]} end, function() return key end)
	end

	function BucketType:GetKey(bucket)
		return self:ChooseLazy(function() return `[bucket].key end, function() return bucket end)
	end

	return BucketType
end

-- Note for myself in the future, because I've done this at least five times now:
-- No, you cannot simplify everything by condensing `KeyType` and `ValueType` into a single `BucketType`.
-- IT. DOES. NOT. WORK.
-- It works for every single function *except* `lookup_handle`. `lookup_handle` determines not just where 
-- a potentially new key/value is supposed to go, but also what the value associated with the given key is.
-- A `get` method that required you to specify the key AND the value would be pretty useless wouldn't it?

function M.Implementation.DenseHashTable(KeyType, ValueType, HashFn, EqFn, Alloc)
	local MetadataHashBitmap = constant(uint8, 127) -- 0b01111111
	local MetadataEmpty = constant(uint8, 128) -- 0b10000000
	local GroupLength = constant(uint, 16)

	local BucketType = M.Implementation.BucketType(KeyType, ValueType)
	local CreateBucket = macro(function (key, value) return BucketType:CreateBucket(key, value) end)
	local GetBucketKey = macro(function (bucket) return BucketType:GetKey(bucket) end)
	local IsKeyEq = macro(function(key, bucket)
		return `[EqFn]([key], GetBucketKey(bucket))
	end)

	local struct DenseHashTable(O.Object) {
		-- The total number of buckets in the table.
		capacity: uint
		-- The number of items stored in the table
		size: uint
		-- Pointer to free on destruction
		opaque_ptr: &opaque
		-- Array of bytes holding the metadata of the table.
		metadata: &uint8
		-- The backing array of the hashtable.
		buckets: &BucketType.TerraType
	}

	local struct HashResult {
		initial_bucket_index: uint
		h1: uint
		h2: uint8
	}

	local struct BucketIndex {
		index: uint
		hash_result: HashResult
	}

	-- A triple containing an opaque pointer to pass to `free`, a pointer to a metadata array, and a pointer to a bucket array
	local CallocResult = R.MakeResult(tuple(&opaque, &uint8, &BucketType.TerraType), int) 
	-- Return value of lookup_handle 
	local BucketHandle = R.MakeResult(BucketIndex, int)
	-- Return value of retrieve_handle
	local RetrieveResult = BucketType:Choose(R.MakeResult(tuple(KeyType, ValueType), int), R.MakeResult(KeyType, int))

	-- Allocates and initalizes memory for the hashtable. The metadata array is initalized to `MetadataEmpty`. Buckets are not initialized to any value.
	local terra table_calloc(capacity: uint): CallocResult 
		var opaque_ptr = Alloc:alloc_raw(capacity * (sizeof(BucketType.TerraType) + 1))
		
		if opaque_ptr == nil then
			return CallocResult.err(1)
		end

		var metadata_array = [&uint8](opaque_ptr)
		var buckets_array = [&BucketType.TerraType](metadata_array + capacity)

		CStr.memset(metadata_array, MetadataEmpty, capacity)

		return CallocResult.ok{opaque_ptr, metadata_array, buckets_array}
	end

	local terra compute_hash(key: KeyType, capacity: uint): HashResult
		var hash = [ HashFn ](key)

		return HashResult {
			initial_bucket_index = (hash >> 7) % capacity,
			h1 = hash >> 7,
			h2 = hash and MetadataHashBitmap
		}
	end

	-- Assigns all the fields of the hashtable to the specified values.
	-- This is done because I'm not sure if I can reuse "self:_init" and we need saftey when mangling the internals in resize.
	local terra reassign_internals(htable: &DenseHashTable, capacity: uint, size: uint, opaque_ptr: &opaque, metadata: &uint8, buckets: &BucketType.TerraType)
		htable.capacity = capacity
		htable.size = size
		htable.opaque_ptr = opaque_ptr
		htable.metadata = metadata
		htable.buckets = buckets
	end

	terra DenseHashTable:init()
		var initial_capacity = GroupLength
		var calloc_result = table_calloc(initial_capacity)

		-- We are just assuming that the memory allocation succeeded. If it didn't then something much bigger is happening. 
		var opaque_ptr, metadata, buckets = calloc_result.ok

		self:_init {
			capacity = initial_capacity,
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

		CStr.memset(self, 0, sizeof(DenseHashTable))
	end

	terra DenseHashTable:lookup_handle(key: KeyType): BucketHandle 
		var hash_result = compute_hash(key, self.capacity)
		var virtual_limit = self.capacity + hash_result.initial_bucket_index

		for virtual_index = hash_result.initial_bucket_index, virtual_limit do
			var index = virtual_index and (self.capacity - 1)
			var metadata = self.metadata[index]

			if metadata == MetadataEmpty or (metadata == hash_result.h2 and IsKeyEq(key, self.buckets[index])) then
				return BucketHandle.ok(BucketIndex {index, hash_result})
			end
		end

		return BucketHandle.err(1)
	end

	local StoreHandleBody = macro(function(self, handle, key, value) 
		return quote
			if [handle]:is_err() then
				return [handle].err
			end

			var bucket_index = [handle].ok 
			var index = bucket_index.index
			var hash_result = bucket_index.hash_result
			var previous_metadata = self.metadata[index]	

			[self].metadata[index] = hash_result.h2
			[self].buckets[index] = CreateBucket(key, value)

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
	else
		terra DenseHashTable:store_handle(handle: BucketHandle, key: KeyType): int
			StoreHandleBody(self, handle, key, nil)
		end
	end

	terra DenseHashTable:retrieve_handle(handle: BucketHandle): RetrieveResult
		if handle:is_err() then
			return RetrieveResult.err(handle.err)
		end

		var bucket = self.buckets[handle.ok.index]
		return RetrieveResult.ok([BucketType:Match(
									`bucket,
									function(s) return `{[s].key, [s].value} end,
									function(k) return k end)])
	end

	terra DenseHashTable:resize(): int
		var old_size = self.size
		var old_capacity = self.capacity
		var old_opaque_ptr = self.opaque_ptr
		var old_metadata = self.metadata
		var old_buckets = self.buckets

		var new_capacity = self.capacity * 2
		var calloc_result = table_calloc(new_capacity)

		if calloc_result:is_err() then
			return calloc_result.err
		end

		var new_opaque_ptr, new_metadata, new_buckets = calloc_result.ok

		reassign_internals(self, new_capacity, 0, new_opaque_ptr, new_metadata, new_buckets)

		for i = 0, old_capacity do
			if old_metadata[i] ~= MetadataEmpty then
				var old_bucket: BucketType.TerraType = old_buckets[i]
				var handle = self:lookup_handle(GetBucketKey(old_bucket))
				var result = [BucketType:Match(
								`old_bucket,
								function(s) return `self:store_handle(handle, [s].key, [s].value) end,
								function(k) return `self:store_handle(handle, [k]) end)]

				if result ~= 0 then
					-- An error occured when rehashing. Reset the state of the hashtable and return an error.
					reassign_internals(self, old_capacity, old_size, old_opaque_ptr, old_metadata, old_buckets)
					[Alloc]:free(new_opaque_ptr)
					return result
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
	terra DenseHashTable:debug_full_repr()
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

	return DenseHashTable
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
