// demo.js — browser-side usage of 7zz.wasm (multi-threaded)
const $ = (id) => document.getElementById(id);
const status = $('status');
const output = $('output');

async function main() {
  status.textContent = 'SAB=' + (typeof SharedArrayBuffer !== 'undefined') +
    ' crossOriginIsolated=' + (window.crossOriginIsolated || false) + ' — 加载 7zz…';

  let outCodes = [];
  let errCodes = [];
  const zz = await create7zz({
    stdout: (c) => outCodes.push(c),
    stderr: (c) => errCodes.push(c),
    noInitialRun: true,
  });
  const FS = zz.FS;
  FS.mkdir('/work');
  FS.chdir('/work');

  status.textContent = '已加载（多线程可用）';

  $('compress').onclick = runCompress;
  $('decompress').onclick = runDecompress;

  runCompress();
  runDecompress();

  function runCompress() {
    outCodes = [];
    errCodes = [];
    const data = new TextEncoder().encode($('input').value);
    FS.writeFile('/work/in.txt', data);
    const code = zz.callMain(['a', '-t7z', '-m0=zstd', '-mmt4', 'out.7z', 'in.txt']);
    const arc = FS.readFile('/work/out.7z');
    output.textContent = 'compress code=' + code + '\n压缩后: ' + arc.length + ' 字节' +
      '\nout-codes=' + outCodes.length + ' err-codes=' + errCodes.length;
    FS.unlink('/work/out.7z');
  }

  function runDecompress() {
    outCodes = [];
    errCodes = [];
    const data = new TextEncoder().encode($('input').value);
    FS.writeFile('/work/in.txt', data);
    zz.callMain(['a', '-t7z', '-m0=zstd', '-mmt4', 'out.7z', 'in.txt']);
    outCodes = [];
    errCodes = [];
    const code = zz.callMain(['e', '-so', 'out.7z']);
    const text = new TextDecoder().decode(new Uint8Array(outCodes));
    output.textContent = 'decompress code=' + code + '\n解压内容:\n' + text +
      '\n---\nout-codes=' + outCodes.length + ' err-codes=' + errCodes.length +
      '\nerr-text=' + new TextDecoder().decode(new Uint8Array(errCodes)).slice(0, 200);
    FS.unlink('/work/out.7z');
  }
}

main().catch((e) => { status.textContent = '加载失败: ' + e; console.error(e); });
