// index.mjs — package entry: the emcc factory plus the run() wrapper.
//
//   import create7zz, { createApi } from '7zip-zstd-wasm';
//   const zz = await createApi(create7zz);
//   const res = await zz.run(['a', '-tzstd', '-si', 'out.zst'], { stdin: 'hello' });
//
// `7zz.cjs` is the emscripten output (a CommonJS module, hence the extension).
// The wrapper is ESM, so this package is ESM-only: CommonJS callers use
// `await import('7zip-zstd-wasm')`, or plain `require()` on Node >= 22.12.

import create7zz from './7zz.cjs';

export { createApi } from './7zz-api.mjs';
export { create7zz };
export default create7zz;
