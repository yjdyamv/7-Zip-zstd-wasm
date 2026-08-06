# Patches

## Active (required for the MT build)

- `sysinfo_shim.c` — provides `sysinfo()` (emscripten libc lacks it); compiled
  into the build via `MY_LIBS`. It reports the wasm heap as the system RAM
  size. Also `-DACCESSPERMS=0777` is passed on the compile line (glibc macro
  missing in musl).
- `0004-flzma2-clamp-threads.patch` — clamp FLZMA2 thread counts so `-mmt=on`
  does not exceed the wasm memory ceiling (applied by `build-wasm.sh`).
- `0007-flzma2-dictsize-max.patch` — clamp the FLZMA2 dictionary to the
  library's 32-bit maximum (128 MiB) so streams >= 128 MiB with a bigger
  requested dictionary do not fail with E_INVALIDARG (applied by
  `build-wasm.sh`).

## Historical (single-threaded / ST build only)

The default build is multi-threaded (no `ST_MODE`), which needs none of these.
They were only needed for a `ST_MODE=1` (single-threaded) wasm build and are
kept here for reference in case someone wants an ST build:

- `0001-zstd-nbWorkers-nonMT.patch` — guard `ZSTD_c_nbWorkers` with
  `#ifdef ZSTD_MULTITHREAD` (zstdmt pool creation fails without pthreads)
- `0002-brotli-numThreads-ST.patch` — guard `_numThreads_WasForced` access in
  `BrotliHandler.cpp` under `Z7_ST`
- `0003-mt-codecs-inline-single-thread.patch` — run lz4/lz5/lizard/brotli MT
  codec workers inline when `threads == 1` (no pthreads in ST wasm builds)
