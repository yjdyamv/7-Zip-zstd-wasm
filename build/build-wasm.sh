#!/bin/bash
# build-wasm.sh — build 7-Zip ZS (7zz/7zr) as WebAssembly (multi-threaded)
#
# Usage:
#   build-wasm.sh --src <7-Zip-zstd checkout> --out <output dir> [--bundle 7zz|7zr] [--emsdk <env script>]
#
# Local and CI share this script. Requires emscripten on PATH (emsdk_env.sh).
set -eu

SRC=""
OUT=""
BUNDLE="7zz"
EMSDK_ENV=""

while [ $# -gt 0 ]; do
  case "$1" in
    --src) SRC="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --bundle) BUNDLE="$2"; shift 2 ;;
    --emsdk) EMSDK_ENV="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

[ -n "$SRC" ] && [ -n "$OUT" ] || { echo "usage: $0 --src <dir> --out <dir> [--bundle 7zz|7zr]" >&2; exit 1; }

if [ -n "$EMSDK_ENV" ]; then
  . "$EMSDK_ENV" 2>/dev/null || true
fi
command -v emcc >/dev/null || { echo "emcc not found; source emsdk_env.sh or pass --emsdk" >&2; exit 1; }

# locate bundle dir
case "$BUNDLE" in
  7zz) BUNDLE_DIR="CPP/7zip/Bundles/Alone2" ;;
  7zr) BUNDLE_DIR="CPP/7zip/Bundles/Alone7z" ;;
  *) echo "unknown bundle: $BUNDLE" >&2; exit 1 ;;
esac
[ -d "$SRC/$BUNDLE_DIR" ] || { echo "not a 7-Zip-zstd checkout: $SRC" >&2; exit 1; }

# common flags (see MT-结论.md):
# - USE_ASM=0            wasm has no x86 asm
# - -fwasm-exceptions    enable C++ exception catching
# - -pthread             multi-threaded (default MT build, -mmt works)
# - -sSTACK_SIZE         flzma2 needs a deep stack
# - -DACCESSPERMS=0777   glibc macro missing in emscripten's musl
# - sysinfo shim         emscripten libc lacks sysinfo()
CFLAGS_BASE2="-DACCESSPERMS=0777 -fwasm-exceptions -pthread"
CXXFLAGS_BASE2="-DACCESSPERMS=0777 -fwasm-exceptions -pthread"
LINK_FLAGS="-pthread -fwasm-exceptions -sUSE_PTHREADS=1 -sPTHREAD_POOL_SIZE=4 \
  -sSTACK_SIZE=8388608 -sMODULARIZE -sEXPORT_NAME=create$BUNDLE \
  -sENVIRONMENT=node,web -sALLOW_MEMORY_GROWTH -sINITIAL_MEMORY=134217728 \
  -sINVOKE_RUN=0 -sEXPORTED_FUNCTIONS=_main -sEXPORTED_RUNTIME_METHODS=FS,callMain"

SHIM_SRC="$(cd "$(dirname "$0")" && pwd)/patches/sysinfo_shim.c"

echo "== building $BUNDLE (wasm, multi-threaded) from $SRC"
cd "$SRC/$BUNDLE_DIR"
rm -rf _o
mkdir -p _o
emcc -O2 -c -o _o/sysinfo_shim.o "$SHIM_SRC"
make CC=emcc CXX=em++ -f makefile.gcc USE_ASM=0 \
  CFLAGS_WARN_WALL= LFLAGS_STRIP= FLAGS_FLTO= \
  CFLAGS_BASE2="$CFLAGS_BASE2" CXXFLAGS_BASE2="$CXXFLAGS_BASE2" \
  MY_LIBS="_o/sysinfo_shim.o" \
  LIB2="$LINK_FLAGS"

# package outputs: rename to canonical names
mkdir -p "$OUT"
cp _o/$BUNDLE "$OUT/$BUNDLE.js"
cp _o/$BUNDLE.wasm "$OUT/$BUNDLE.wasm"
cp "$(cd "$(dirname "$0")" && pwd)/../src/7zz-api.js" "$OUT/7zz-api.js"
cp "$SRC/COPYING" "$OUT/LICENSE" 2>/dev/null || true
echo "== done: $OUT/$BUNDLE.js + $OUT/$BUNDLE.wasm"
