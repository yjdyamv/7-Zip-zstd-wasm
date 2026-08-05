// test-wasm.js — smoke test for the packaged 7zz.wasm build
// Usage: node test/test-wasm.js [path-to-build-dir]
import { createRequire } from 'module';
import { createApi } from '../src/7zz-api.js';

const require = createRequire(import.meta.url);
const { fileURLToPath } = await import('node:url');
const { resolve } = await import('node:path');
// resolve relative to CWD (repo root when run from CI: `node test/test-wasm.js out`)
const buildDir = process.argv[2] ? resolve(process.argv[2]) : fileURLToPath(new URL('../out/', import.meta.url));

const { default: create7zz } = await import(require.resolve(buildDir + '/7zz.js'));
const zz = await createApi(create7zz);

let pass = 0, fail = 0;
function check(name, ok, extra) {
  if (ok && extra && !extra()) ok = false;
  if (ok) { pass++; console.log('PASS', name); }
  else { fail++; console.log('FAIL', name); }
}

const data = new TextEncoder().encode('Hello 7-Zip WASM! '.repeat(500));
let r = await zz.run(['a', '-t7z', '-m0=zstd', '-mmt4', 'out.7z', 'in.txt'], { files: { 'in.txt': data } });
check('create 7z+zstd+mmt4', r.code === 0 && r.files['out.7z']);
r = await zz.run(['t', 'out.7z']);
check('test archive', r.code === 0 && /Everything is Ok/.test(r.stdout));
r = await zz.run(['e', '-so', 'out.7z']);
check('extract -so', r.code === 0 && r.stdout.includes('Hello 7-Zip WASM!'));
r = await zz.run(['a', '-tzstd', '-si', 'stream.zst'], { stdin: 'hello stdin stream!' });
check('zstd -si create', r.code === 0 && (r.files['stream.zst'] || []).length > 0);
r = await zz.run(['e', '-so', 'stream.zst']);
check('zstd -si extract', r.code === 0 && r.stdout.includes('hello stdin stream!'));
const info = await zz.run(['i']);
const threadsMatch = info.stdout.match(/Threads:\s*(\d+)/);
check('multi-threaded build', !!threadsMatch && parseInt(threadsMatch[1], 10) > 1);

console.log('\nRESULT: pass=' + pass + ' fail=' + fail);
process.exit(fail ? 1 : 0);
