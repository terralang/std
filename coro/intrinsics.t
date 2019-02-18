

local corosize = terralib.intrinsic("llvm.coro.size.i32", {} -> {int32})
local token = terralib.irtypes.primitive("token", terralib.sizeof(intptr), false)

local intrinsics = {
    destroy = terralib.intrinsic("llvm.coro.destroy", {&int8} -> {}),
    done = terralib.intrinsic("llvm.coro.done", {&int8} -> {}),
    promise = terralib.intrinsic("llvm.coro.promise", {&int8, int32, bool} -> {&int8}),
    size = corosize,
    begin = terralib.intrinsic("llvm.coro.begin", {token, &int8} -> &int8),
    free = terralib.intrinsic("llvm.coro.free", {token, &int8} -> &int8),
    alloc = terralib.intrinsic("llvm.coro.alloc", token -> bool),
    frame = terralib.intrinsic("llvm.coro.frame", {} -> &int8),
    id = terralib.intrinsic("llvm.coro.id", {int32, &int8, &int8, &int8} -> token),
    End = terralib.intrinsic("llvm.coro.end", {&int8, bool} -> bool),
    suspend = terralib.intrinsic("llvm.coro.suspend", {token, bool} -> int8),
    save = terralib.intrinsic("llvm.coro.save", &int8 -> token),
    param = terralib.intrinsic("llvm.coro.param", {&int8, &int8} -> bool),
}

return intrinsics
