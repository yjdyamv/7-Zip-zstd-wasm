# 7-Zip ZS — WebAssembly

[7-Zip ZS](https://github.com/mcmilk/7-Zip-zstd) (7-Zip with Zstandard, Brotli, LZ4, LZ5, Lizard, fast-lzma2) compiled to WebAssembly — **multi-threaded**, with an in-memory JS API.

This repository only contains the build tooling; the source is pulled from upstream `mcmilk/7-Zip-zstd` release tags. **Releases here use the same tag names as upstream** (e.g. `v26.02-v1.5.7-R2`), so a wasm build is published for every upstream release.

## Features

- Full-featured `7zz` (all formats: 7z, zip, tar, gzip, bzip2, xz, zstd, brotli, lz4, lz5, lizard, wim, rar read, ...) and minimal `7zr`
- **Multi-threaded by default**: `-mmt` works, zstd/lz4/lz5/lizard/brotli MT codecs included
- Memory-only I/O via the JS API: no disk access needed, files passed as `Uint8Array`
- `-si`/`-so` stdin/stdout streaming, binary-safe capture
- Runs in Node (worker_threads backend) and browsers (SharedArrayBuffer)

## Usage

### Node

```js
import create7zz from './7zz.js';          // MODULARIZE factory (CJS import)
import { createApi } from './7zz-api.js';

const zz = await createApi(create7zz);
const res = await zz.run(['a', '-t7z', '-m0=zstd', '-mmt4', 'out.7z', 'in.txt'], {
  files: { 'in.txt': new Uint8Array([...]) },  // inputs land in the virtual /work
  stdin: 'stdin data',                          // feeds 7zz's stdin (-si)
});
// res = { code, stdout, stderr, files: { 'out.7z': Uint8Array } }
// res.files contains only files created/changed by this run
```

### Browser

Browsers require **SharedArrayBuffer** (serve with `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp`). The worker code is embedded in `7zz.js`.

```html
<script src="7zz.js"></script>
<script src="7zz-api.js"></script>
<script>
  const zz = await createApi(create7zz);
  const res = await zz.run(['a', '-t7z', '-m0=zstd', 'out.7z', 'in.txt'], { files: { 'in.txt': data } });
</script>
```

See `demo/` for a working page (`node demo/server.mjs` then open http://localhost:8080/).

## Build from source

Requires the Emscripten SDK (emsdk, pinned in CI to 3.1.77).

```bash
git clone https://github.com/mcmilk/7-Zip-zstd   # or any tag
source ~/emsdk/emsdk_env.sh
./build/build-wasm.sh --src /path/to/7-Zip-zstd --out out --bundle 7zz
./build/build-wasm.sh --src /path/to/7-Zip-zstd --out out --bundle 7zr
node test/test-wasm.js out
```

Build details: `ST_MODE` off (native MT build), `-pthread -sUSE_PTHREADS=1`, wasm exceptions enabled, 8 MB stack, memory grows from 128 MB. No upstream source patches are needed. Two build-level adapters live in `build/patches/`:

- `-DACCESSPERMS=0777` — glibc macro missing in emscripten's musl
- `sysinfo_shim.c` — emscripten libc lacks `sysinfo()` (reports 4 GB RAM)

## Release automation

`.github/workflows/sync-upstream.yml` polls `mcmilk/7-Zip-zstd` releases (every 6 h or manual dispatch), builds the new tag and publishes a release here under the identical tag name. `.github/workflows/ci.yml` builds and tests on every push.

## Limits

- wasm memory cap 4 GB; single WebAssembly module, so formats that need very large dictionaries may fail on small devices
- Browser multi-threading requires cross-origin isolation (COOP/COEP)
- LZMA/Cpio/Ar creation and compressed-tar creation are not supported by 7-Zip 26.x upstream (matches native behavior)
