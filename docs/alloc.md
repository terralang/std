Alloc
=====

Alloc is the module in charge of interacting with raw memory allocations.

This module defines the API for allocators, defines a default allocator, and
defines convenience functions for creating an allocator.

It provides a simple API for memory management that has sensible defaults and type awareness,
a lower level raw API, and a more configurable API with support for dependency injection.

An Allocator is a type. There is no restriction on the members contained in it, but making it
a zero size type is potentially useful. The required methods are alloc_raw, free_raw, and realloc_raw.
All other methods are generated from these methods and default implementations if they are not present.
The full methods list include normal and raw variants of alloc, free, clear, calloc, copy, and realloc
as well as new and delete which do not have a raw variant. The default implementations are made using
macros that support elimination of the self parameter if it is unused in the implementation.
The default copy and clear implementations are normal terra code that depends on LLVM to optimize
them to good performance. It is usually not necessary to replace them unless the allocator
has access to something that would optimize them like a DMA engine.

The copy and clear calls were included in the specification because they can be optimized
using the same low level hardware access and kernel calls that the rest of the allocator
methods would need, including them permits autoderivation of several methods from a smaller
subset which eases implementation, and they are similar low level memory access which
needs to be compartmentalized for the same reasons as the rest of allocation.

`allocator:copy()` should not be confused with `object:clone()`.
copy is a direct memory to memory shallow copy. clone is a semantically aware object clone.
copy may copy unnecessary bits of memory if the object's current state uses less than the full
size. Copy may violate assumptions of pointer ownership in an object. Copy is primarily applicable
when using a raw pointer buffer containing value types. Using a container type and/or using clone
is likely better than using copy, but copy is useful for low level interfaces and building other
allocator functions, and so it is included.

`allocator:clear()` and `object:init()` should not be confused. Init sets the memory of the object
to a meaningful initial state. Clear sets it to all zeros, which may or may not be a valid state,
but is at least a consistently known one.

`allocator:clear()` and `object:destruct()` should not be confused. Destruct releases any external
resources held by the object, but does not need to leave it in any known state or destroy all sensitive
data. Clear does not release any external resources, but does destroy the data held in the object.
For any security critical operation, an additional operation shred which both releases resources
and destroys the data stored inside the object and in any owned pointers is recommended.

`allocator:new()` is a combination of alloc and init; `allocator:delete()` is a combination of destruct and free.

Unlike the C realloc, the allocator:realloc call accepts both an old and new size, and does not accept a pointer
not given by an allocation call from the same allocator. in C `realloc(NULLPTR, size)` is the same as `malloc(size)`
and `realloc(ptr, 0)` is the same as `free(ptr)`,
but in terra `realloc(nil, 0, size)` is not the same as `alloc(T, size)` but is undefined
and `realloc(ptr, size, 0)` is not the same as `free(ptr)`. Realloc has an extra parameter over the
C version both because the extra parameter may permit additional optimizations in some implementations
and because the parameter allows realloc to be autoderived.
