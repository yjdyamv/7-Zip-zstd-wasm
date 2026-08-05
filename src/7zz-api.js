// 7zz-api.js — JS wrapper for the 7-Zip ZS WASM build (7zz.wasm)
//
// Usage (Node ESM):
//   import create7zz from './7zz.mjs';       // MODULARIZE factory
//   import { createApi } from './7zz-api.mjs';
//   const zz = await createApi(create7zz);
//   const res = await zz.run(['a', '-t7z', '-m0=zstd', 'out.7z', 'in.txt'], {
//     files: { 'in.txt': new Uint8Array([...]) },   // in-memory inputs
//     stdin: 'stdin data',                          // feeds 7zz's stdin (-si)
//   });
//   // res = { code, stdout, stderr, files: { 'out.7z': Uint8Array } }
//
// stdout/stderr are captured byte-exact via the emscripten FS stream hooks
// (Module['stdout']/Module['stderr'] are char-code callbacks). Binary output
// (e.g. `e -so`) is preserved losslessly. res.files contains only files that
// were created/changed by this run (snapshot-diff of the virtual work dir).
// Browser bundlers can use the same API (7zz.mjs is the MODULARIZE output).

const WORK_DIR = '/work';
const FILE_SEP = '/';

function toU8(data) {
  if (data instanceof Uint8Array) return data;
  if (typeof data === 'string') return new TextEncoder().encode(data);
  if (ArrayBuffer.isView(data)) return new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
  if (data instanceof ArrayBuffer) return new Uint8Array(data);
  throw new TypeError('unsupported input type: ' + typeof data);
}

export async function createApi(factory, opts = {}) {
  const workDir = opts.workDir || WORK_DIR;
  let stdinBytes = new Uint8Array(0);
  let stdinPos = 0;
  let outCodes = [];
  let errCodes = [];

  const mod = await factory({
    stdin: () => (stdinPos < stdinBytes.length ? stdinBytes[stdinPos++] : null),
    stdout: (c) => outCodes.push(c),
    stderr: (c) => errCodes.push(c),
    noInitialRun: true,
  });

  const FS = mod.FS;
  if (!FS.analyzePath(workDir).exists) FS.mkdir(workDir);

  function ensureDir(path) {
    const parts = path.split(FILE_SEP).filter(Boolean);
    let cur = '';
    for (const p of parts) {
      cur += FILE_SEP + p;
      if (!FS.analyzePath(cur).exists) FS.mkdir(cur);
    }
  }

  function listFiles(dir, prefix) {
    const res = {};
    for (const name of FS.readdir(dir)) {
      if (name === '.' || name === '..') continue;
      const full = dir + FILE_SEP + name;
      const st = FS.stat(full);
      if (FS.isDir(st.mode)) Object.assign(res, listFiles(full, prefix + name + FILE_SEP));
      else res[prefix + name] = { size: st.size, mtime: st.mtime, data: null };
    }
    return res;
  }

  function snapshot() {
    const snap = listFiles(workDir, '');
    for (const [path, v] of Object.entries(snap)) {
      v.data = new Uint8Array(FS.readFile(workDir + FILE_SEP + path));
    }
    return snap;
  }

  function diff(snap) {
    const now = listFiles(workDir, '');
    const res = {};
    for (const [path, st] of Object.entries(now)) {
      const prev = snap[path];
      const sameTime = prev && prev.size === st.size &&
        prev.mtime.getTime() === st.mtime.getTime();
      if (!sameTime) {
        const data = new Uint8Array(FS.readFile(workDir + FILE_SEP + path));
        if (!prev || !Buffer.from(data).equals(Buffer.from(prev.data))) {
          res[path] = data;
        }
      }
    }
    return res;
  }

  function decode(codes) {
    return new TextDecoder('utf-8', { fatal: false }).decode(Uint8Array.from(codes));
  }

  return {
    version: opts.version || 'unknown',
    workDir,
    async run(argv, input = {}) {
      outCodes.length = 0;
      errCodes.length = 0;
      stdinBytes = input.stdin ? toU8(input.stdin) : new Uint8Array(0);
      stdinPos = 0;
      const before = snapshot();
      try {
        FS.chdir(workDir);
        for (const [path, data] of Object.entries(input.files || {})) {
          const target = (workDir + FILE_SEP + path).replace(/\/+/g, '/');
          ensureDir(target.slice(0, target.lastIndexOf(FILE_SEP)));
          FS.writeFile(target, toU8(data));
        }
        const code = mod.callMain(argv);
        return { code, stdout: decode(outCodes), stderr: decode(errCodes), files: diff(before) };
      } finally {
        stdinBytes = new Uint8Array(0);
      }
    },
  };
}

export default createApi;
