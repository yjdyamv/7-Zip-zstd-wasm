# 7-Zip ZS — WebAssembly

[7-Zip ZS](https://github.com/mcmilk/7-Zip-zstd) (7-Zip with Zstandard, Brotli, LZ4, LZ5, Lizard, fast-lzma2) compiled to WebAssembly — **multi-threaded**, with an in-memory JS API.

This repository only contains the build tooling; the source is pulled from upstream `mcmilk/7-Zip-zstd` release tags. **Releases here use the same tag names as upstream** (e.g. `v26.02-v1.5.7-R2`), so a wasm build is published for every upstream release.

## Features

- Full-featured `7zz` (all formats: 7z, zip, tar, gzip, bzip2, xz, zstd, brotli, lz4, lz5, lizard, wim, rar read, ...)
- **Multi-threaded by default**: `-mmt` works, zstd/lz4/lz5/lizard/brotli MT codecs included
- Memory-only I/O via the JS API: no disk access needed, files passed as `Uint8Array`
- `-si`/`-so` stdin/stdout streaming, binary-safe capture
- Runs in Node (worker_threads backend) and browsers (SharedArrayBuffer)

## Usage

### npm

```bash
npm install 7zip-zstd-wasm
```

```js
import create7zz, { createApi } from '7zip-zstd-wasm';

const zz = await createApi(create7zz);
const res = await zz.run(['a', '-tzstd', '-si', 'out.zst'], { stdin: 'hello' });
```

The package is ESM-only: CommonJS callers use `await import('7zip-zstd-wasm')`, or plain `require()` on Node >= 22.12. `7zz.cjs` is the emscripten module and `7zz-api.mjs` the wrapper; both are reachable through the entry, and `7zip-zstd-wasm/7zz.wasm` is exported for callers that serve the binary themselves.

Every release records the build it came from, so a version number never has to be decoded:

```js
const pkg = await import('7zip-zstd-wasm/package.json', { with: { type: 'json' } });
pkg.default['7zip'];
// { upstreamTag: 'v26.05-v1.5.7-R1', upstreamCommit: '07f03a4…',
//   revision: 1, zstd: '1.5.7', emsdk: '6.0.5', buildRepoCommit: '253e360…' }
```

### From a release tarball

The three files from the Releases page work the same way without npm:

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

Requires the Emscripten SDK (emsdk, pinned in CI to 6.0.5 — see `build/emsdk-version`).

```bash
git clone https://github.com/mcmilk/7-Zip-zstd   # or any tag
source ~/emsdk/emsdk_env.sh
./build/build-wasm.sh --src /path/to/7-Zip-zstd --out out --bundle 7zz
node test/test-wasm.js out
```

Build details: `ST_MODE` off (native MT build), `-pthread -sUSE_PTHREADS=1`, wasm exceptions enabled, 8 MB stack, memory grows from 128 MB. No upstream source patches are needed. Two build-level adapters live in `build/patches/`:

- `-DACCESSPERMS=0777` — glibc macro missing in emscripten's musl
- `sysinfo_shim.c` — emscripten libc lacks `sysinfo()` (reports 4 GB RAM)

## Release automation

`.github/workflows/sync-upstream.yml` polls `mcmilk/7-Zip-zstd` releases (monthly, plus manual dispatch for anything needed sooner), builds the new tag, publishes a release here under the identical tag name, and then publishes the same bytes to npm. `.github/workflows/ci.yml` builds and tests on every push.

npm versions are a counter, not a transcription of the tag: `v26.05-v1.5.7-R1` becomes `26.5.0` (7-Zip 26.5, first publish on that line), the next publish on the same 7-Zip line becomes `26.5.1` whichever reason it had, and `v26.06-…` restarts at `26.6.0`. Upstream's exact identity lives in the `7zip` field above. The mapping is `scripts/ci/npm-version-from-tag.sh` and it is the only place that rule exists; it also refuses to go backwards when upstream publishes a revision for an older 7-Zip line.

Two npm facts the workflow has to live with: a name that does not exist yet cannot be published through the workflow's OIDC identity (npm only exchanges a trusted-publisher token for an existing package), so the very first publish of `7zip-zstd-wasm` is done by hand with a granular token; and a published version can never be replaced, so re-running a job skips whatever is already on the registry instead of failing.

## Limits

- wasm memory cap 4 GB; single WebAssembly module, so formats that need very large dictionaries may fail on small devices
- Browser multi-threading requires cross-origin isolation (COOP/COEP)
- LZMA/Cpio/Ar creation and compressed-tar creation are not supported by 7-Zip 26.x upstream (matches native behavior)
