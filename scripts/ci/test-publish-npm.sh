#!/bin/bash
# test-publish-npm.sh — the publish script is the only thing that touches the
# registry, so its rules get tests. Run from anywhere:
#   bash scripts/ci/test-publish-npm.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
script="$here/publish-npm.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tmp="$(cd "$tmp" && { pwd -W 2>/dev/null || pwd; })"

pass=0
fail=0
check() { # check <desc> <needle> <haystack>
  if printf '%s' "$3" | grep -qF -- "$2"; then
    pass=$((pass + 1))
    printf 'PASS %s\n' "$1"
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n     missing: %s\n     in: %s\n' "$1" "$2" "$3"
  fi
}
check_absent() { # check_absent <desc> <needle> <haystack>
  if printf '%s' "$3" | grep -qF -- "$2"; then
    fail=$((fail + 1))
    printf 'FAIL %s\n     unexpected: %s\n' "$1" "$2"
  else
    pass=$((pass + 1))
    printf 'PASS %s\n' "$1"
  fi
}
expect_failure() { # expect_failure <desc> <command...>
  local desc="$1"
  shift
  if "$@" >"$tmp/out.log" 2>&1; then
    fail=$((fail + 1))
    printf 'FAIL %s (it succeeded)\n' "$desc"
  else
    pass=$((pass + 1))
    printf 'PASS %s\n' "$desc"
  fi
}

# --- a build payload ------------------------------------------------------
payload="$tmp/payload"
mkdir -p "$payload"
printf 'module.exports = function create7zz() { return Promise.resolve({}); };\n' >"$payload/7zz.js"
printf 'export function createApi() { return {}; }\nexport default createApi;\n' >"$payload/7zz-api.js"
printf '\000asm\001' >"$payload/7zz.wasm"
printf 'GNU LGPL\n' >"$payload/LICENSE"

# --- a stub npm: `view` reports what $FAKE_PUBLISHED says, `publish` records
mkdir -p "$tmp/stub"
cat >"$tmp/stub/npm" <<'STUB'
#!/bin/bash
printf '%s\n' "npm $*" >>"$FAKE_LOG"
case "$1" in
  view)
    want="$2"
    if [ -f "$FAKE_PUBLISHED" ] && grep -qxF "$want" "$FAKE_PUBLISHED"; then
      echo "0.0.1"
      exit 0
    fi
    if [ -f "$FAKE_VERSIONS" ] && [ "${want##*@}" = "$want" ]; then
      cat "$FAKE_VERSIONS"
      exit 0
    fi
    echo "npm error code E404" >&2
    echo "npm error 404 Not Found - GET https://registry.npmjs.org/$want" >&2
    exit 1
    ;;
  publish)
    printf 'published %s\n' "$(node -e "process.stdout.write(require('./package.json').name + '@' + require('./package.json').version)")"
    exit 0
    ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$tmp/stub/npm"
: >"$tmp/published-nothing"

run_publish() { # run_publish <stage> [extra args...]
  local stage="$1"
  shift
  env NPM="$tmp/stub/npm" FAKE_LOG="$tmp/npm.log" \
    FAKE_PUBLISHED="${FAKE_PUBLISHED:-$tmp/published-nothing}" \
    FAKE_VERSIONS="${FAKE_VERSIONS:-$tmp/no-versions}" \
    NPM_STAGE_DIR="$stage" NODE_AUTH_TOKEN=fake \
    UPSTREAM_COMMIT=deadbeef BUILD_REPO_COMMIT=cafebabe \
    bash "$script" "$@" "$payload" v26.05-v1.5.7-R1
}

# 1. a first dry run stages the package and reports the tag-derived version
out="$(run_publish "$tmp/stage1" --dry-run 2>&1)"
check "dry run reports the tag-derived version" "would publish 7zip-zstd-wasm 26.5.0" "$out"
check_absent "dry run publishes nothing" "npm publish" "$(cat "$tmp/npm.log" 2>/dev/null || true)"

# 2. the staged package is the npm shape, not the build shape
[ -f "$tmp/stage1/7zz.cjs" ] && { pass=$((pass + 1)); printf 'PASS the emcc output is staged as .cjs\n'; } ||
  { fail=$((fail + 1)); printf 'FAIL the emcc output is staged as .cjs\n'; }
[ -f "$tmp/stage1/7zz-api.mjs" ] && { pass=$((pass + 1)); printf 'PASS the api wrapper is staged as .mjs\n'; } ||
  { fail=$((fail + 1)); printf 'FAIL the api wrapper is staged as .mjs\n'; }
[ ! -f "$tmp/stage1/7zz.js" ] && { pass=$((pass + 1)); printf 'PASS no stale .js copy is left behind\n'; } ||
  { fail=$((fail + 1)); printf 'FAIL a stale .js copy was staged\n'; }

# 3. the manifest carries where the bytes came from
manifest="$(cat "$tmp/stage1/package.json")"
check "version is in the manifest" '"version": "26.5.0"' "$manifest"
check "the upstream tag is recorded" '"upstreamTag": "v26.05-v1.5.7-R1"' "$manifest"
check "the zstd version is recorded" '"zstd": "1.5.7"' "$manifest"
check "the revision is recorded" '"revision": 1' "$manifest"
check "the upstream commit is recorded" '"upstreamCommit": "deadbeef"' "$manifest"
check "the build commit is recorded" '"buildRepoCommit": "cafebabe"' "$manifest"

# 4. the README that ships is the repo's, since npm only shows the package one
cmp -s "$tmp/stage1/README.md" "$root/README.md" &&
  { pass=$((pass + 1)); printf 'PASS the README comes from the repo root\n'; } ||
  { fail=$((fail + 1)); printf 'FAIL the staged README is not the repo one\n'; }

# 5. a version that is already published is skipped, not re-uploaded
printf '7zip-zstd-wasm@26.5.0\n' >"$tmp/published-one"
export FAKE_PUBLISHED="$tmp/published-one"
out="$(run_publish "$tmp/stage2" --dry-run 2>&1)"
check "an existing version is skipped" "skip  7zip-zstd-wasm 26.5.0" "$out"
export FAKE_PUBLISHED="$tmp/published-nothing"

# 6. the counter continues from what the registry already has
printf '["26.5.0","26.5.1"]\n' >"$tmp/versions-two"
export FAKE_VERSIONS="$tmp/versions-two"
out="$(run_publish "$tmp/stage3" --dry-run 2>&1)"
check "the counter continues from the registry" "would publish 7zip-zstd-wasm 26.5.2" "$out"
export FAKE_VERSIONS="$tmp/no-versions"

# 7. a broken payload never reaches the registry
mv "$payload/7zz.wasm" "$payload/7zz.wasm.bak"
expect_failure "a payload without the wasm is rejected" run_publish "$tmp/stage4" --dry-run
grep -q 'the payload has no 7zz.wasm' "$tmp/out.log" &&
  { pass=$((pass + 1)); printf 'PASS the missing wasm is named\n'; } ||
  { fail=$((fail + 1)); printf 'FAIL the error does not name the missing wasm\n'; }
mv "$payload/7zz.wasm.bak" "$payload/7zz.wasm"

# 8. a manifest that lists a file the payload does not have is rejected
rm -rf "$tmp/root2"
mkdir -p "$tmp/root2/build" "$tmp/root2/scripts"
cp -r "$root/pkg" "$tmp/root2/pkg"
cp "$root/README.md" "$tmp/root2/README.md"
cp "$root/build/emsdk-version" "$tmp/root2/build/emsdk-version"
cp -r "$root/scripts/ci" "$tmp/root2/scripts/ci"
node -e '
const fs = require("fs");
const pkg = require(process.argv[1]);
pkg.files.push("NOTICE");
fs.writeFileSync(process.argv[2], JSON.stringify(pkg, null, 2));
' "$root/pkg/package.json" "$tmp/root2/pkg/package.json"
expect_failure "a files entry with no counterpart is rejected" \
  env ROOT="$tmp/root2" NPM="$tmp/stub/npm" FAKE_LOG="$tmp/npm.log" \
  FAKE_PUBLISHED="$tmp/published-nothing" FAKE_VERSIONS="$tmp/no-versions" \
  NPM_STAGE_DIR="$tmp/stage5" NODE_AUTH_TOKEN=fake \
  bash "$script" --dry-run "$payload" v26.05-v1.5.7-R1
grep -q 'lists NOTICE but there is no such file' "$tmp/out.log" &&
  { pass=$((pass + 1)); printf 'PASS the missing files entry is named\n'; } ||
  { fail=$((fail + 1)); printf 'FAIL the error does not name the missing entry\n'; }

# 9. with credentials and no dry run, exactly one publish happens
: >"$tmp/npm.log"
out="$(run_publish "$tmp/stage6" 2>&1)"
check "the publish is announced" "done: 7zip-zstd-wasm 26.5.0" "$out"
if [ "$(grep -c '^npm publish' "$tmp/npm.log")" = 1 ]; then
  pass=$((pass + 1))
  printf 'PASS npm publish ran exactly once\n'
else
  fail=$((fail + 1))
  printf 'FAIL npm publish ran %s time(s)\n' "$(grep -c '^npm publish' "$tmp/npm.log")"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
