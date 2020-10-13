local ffi = require 'ffi'
local C = nil
local T = {}

if ffi.os == "Windows" then
C = terralib.includecstring [[
#include <stdint.h>

#pragma pack(push)
#pragma pack(8)
#define WINVER        0x0601 //_WIN32_WINNT_WIN7
#define _WIN32_WINNT  0x0601
#define NTDDI_VERSION 0x06010000 // NTDDI_WIN7
#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX // Some compilers enable this by default
  #define NOMINMAX
#endif
#define NOBITMAP
#define NOMCX
#define NOSERVICE
#define NOHELP
#include <windows.h>
#pragma pack(pop)
]]

local terra queryTime() : uint64
  var t : uint64
  C.QueryPerformanceCounter([&C.LARGE_INTEGER](&t))
  return t
end

terra T.OpenProfiler() : uint64
  return queryTime()
end

terra T.CloseProfiler(start : uint64) : uint64
  var freq : uint64 -- This query never changes during program execution, but it's not clear how to do non-constant globals
  C.QueryPerformanceFrequency([&C.LARGE_INTEGER](&freq))
  return ((queryTime() - start) * 1000000000) / freq
end

terra T.ClockNS() : uint64
  return C.GetTickCount64() * 1000000 -- convert to nanoseconds
end
else
C = terralib.includecstring [[
#include <stdint.h>
#include <time.h>

#ifdef _POSIX_MONOTONIC_CLOCK
#ifdef CLOCK_MONOTONIC_RAW
const int T_POSIX_CLOCK = CLOCK_MONOTONIC_RAW;
#else
const int T_POSIX_CLOCK = CLOCK_MONOTONIC;
#endif
#else
const int T_POSIX_CLOCK = CLOCK_REALTIME;
#endif

#ifdef _POSIX_CPUTIME
const int T_POSIX_CLOCK_PROFILER = CLOCK_PROCESS_CPUTIME_ID;
#else
const int T_POSIX_CLOCK_PROFILER = T_POSIX_CLOCK;
#endif
]]

local terra queryTime(clock : C.clockid_t) : uint64
  var tspec : C.timespec
  C.clock_gettime(clock, &tspec)
  return (([uint64](tspec.tv_sec)) * 1000000000) + [uint64](tspec.tv_nsec)
end

terra T.OpenProfiler() : uint64
  return queryTime(C.T_POSIX_CLOCK_PROFILER)
end

terra T.CloseProfiler(start : uint64) : uint64
  return queryTime(C.T_POSIX_CLOCK_PROFILER) - start
end

terra T.ClockNS() : uint64
  return queryTime(C.T_POSIX_CLOCK)
end
end

terra T.Clock() : double
  return T.ClockNS() / 1000000000.0
end

return T