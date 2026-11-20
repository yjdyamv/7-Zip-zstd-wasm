#!/bin/bash
# publish-npm.sh — stage and publish the npm package from a build payload
#
# Usage:
#   publish-npm.sh [--dry-run] <payload-dir> <tag>
#
#   <payload-dir>  the build output directory (build/build-wasm.sh --out <dir>)
#   <tag>          the upstream tag being published, e.g. v26.05-v1.5.7-R1
#
# Environment:
#   NPM                  npm binary (default: npm)
#   ROOT                 repo root (default: the parent of scripts/ci)
#   NPM_PUBLISH_FLAGS    extra `npm publish` flags (CI passes --provenance)
#   NPM_STAGE_DIR        keep the staged package here instead of a temp dir
#                        (tests and manual reproductions use this)
#   UPSTREAM_COMMIT      upstream commit the payload was built from (metadata)
#   BUILD_REPO_COMMIT    this repo's commit (metadata, defaults to $GITHUB_SHA)
#   EMSDK_VERSION        emsdk the payload was built with (metadata, defaults to
#                        the committed build/emsdk-version)
#
# The package is assembled in a staging directory rather than published from
# the repo: the build output lives in `out/` (git-ignored) while the manifest
# lives in `pkg/`, and npm cannot include files from outside the package
# directory, so the two have to be flattened first. Staging also lets the emcc
# output ship as `7zz.cjs` — under `"type": "module"` a `.js` CommonJS file
# imports as `undefined` instead of failing, which is the one way this package
# could break silently.
set -euo pipefail

fail() {
  printf '%s\n' "error: $*" >&2
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    printf '::error::%s\n' "$*"
  fi
  exit 1
}

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(cd "$here/../.." && pwd)}"
NPM="${NPM:-npm}"

abspath() { (cd "$1" 2>/dev/null && { pwd -W 2>/dev/null || pwd; }) || printf '%s' "$1"; }
# pkg_field <manifest> <js expression on `pkg`>
pkg_field() { node -e "process.stdout.write(String(require(process.argv[1]).$2 ?? ''))" "$1"; }

dry_run=0
args=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=1 ;;
    -*) fail "unknown flag: $arg" ;;
    *) args+=("$arg") ;;
  esac
done

[ "${#args[@]}" -eq 2 ] || fail "usage: $0 [--dry-run] <payload-dir> <tag>"
payload="$(abspath "${args[0]}")"
tag="${args[1]}"

manifest="$ROOT/pkg/package.json"
[ -f "$manifest" ] || fail "no $manifest"
[ -d "$payload" ] || fail "no payload directory: ${args[0]}"
name="$(pkg_field "$manifest" name)"
[ -n "$name" ] || fail "$manifest has no name"

# --- the payload must be a complete build --------------------------------
for artifact in 7zz.js 7zz.wasm 7zz-api.js LICENSE; do
  [ -f "$payload/$artifact" ] || fail "the payload has no $artifact (build it first: build/build-wasm.sh --out <dir>)"
done

# --- the version comes from the tag, clamped above whatever is published --
versions="$(mktemp)"
trap 'rm -f "$versions"' EXIT
if ! $NPM view "$name" versions --json >"$versions" 2>"$versions.err"; then
  # Only "this package does not exist yet" may be read as "no versions": a
  # network or auth failure must not turn into a first publish.
  grep -q 'E404' "$versions.err" || fail "could not list published versions of $name: $(head -3 "$versions.err")"
  : >"$versions"
fi
rm -f "$versions.err"
version="$(bash "$ROOT/scripts/ci/npm-version-from-tag.sh" "$tag" "$versions")" ||
  fail "could not derive a version from tag $tag"
[ -n "$version" ] || fail "could not derive a version from tag $tag"

# --- stage the package ---------------------------------------------------
if [ -n "${NPM_STAGE_DIR:-}" ]; then
  stage="$NPM_STAGE_DIR"
  rm -rf "$stage"
  mkdir -p "$stage"
else
  stage="$(mktemp -d)"
  trap 'rm -rf "$stage"; rm -f "$versions"' EXIT
fi
stage="$(abspath "$stage")"

cp "$ROOT/pkg/index.mjs" "$stage/index.mjs"
cp "$ROOT/pkg/index.d.ts" "$stage/index.d.ts"
cp "$ROOT/README.md" "$stage/README.md"
# The emcc output is CommonJS, the wrapper is ESM: the extensions are load
# bearing, not cosmetic.
cp "$payload/7zz.js" "$stage/7zz.cjs"
cp "$payload/7zz-api.js" "$stage/7zz-api.mjs"
cp "$payload/7zz.wasm" "$stage/7zz.wasm"
cp "$payload/LICENSE" "$stage/LICENSE"
if [ -f "$payload/VERSION" ]; then
  cp "$payload/VERSION" "$stage/VERSION"
else
  {
    printf 'tag=%s\n' "$tag"
    printf 'upstream_commit=%s\n' "${UPSTREAM_COMMIT:-unknown}"
    printf 'build_repo_commit=%s\n' "${BUILD_REPO_COMMIT:-${GITHUB_SHA:-unknown}}"
  } >"$stage/VERSION"
fi
# Staged VERSION is the payload's, copied above; make sure the manifest agrees
# with it rather than claiming "unknown".

revision="$(printf '%s' "$tag" | sed -nE 's/.*-R([0-9]+)$/\1/p')"
zstd="$(printf '%s' "$tag" | sed -nE 's/^.*-v([0-9][0-9.]*)-R[0-9]+$/\1/p')"
emsdk="${EMSDK_VERSION:-$(cat "$ROOT/build/emsdk-version" 2>/dev/null || printf 'unknown')}"

# The build writes VERSION next to the payload; prefer it over "unknown" so a
# hand-published package still says where its bytes came from.
version_field() { # version_field <key>
  # `pipefail` turns sed's "no such file" into the pipeline's status, so the
  # guard has to be inside the function or an absent VERSION kills the script.
  [ -f "$payload/VERSION" ] || return 0
  sed -nE "s/^$1=//p" "$payload/VERSION" | head -1 || true
}
upstream="${UPSTREAM_COMMIT:-$(version_field upstream_commit)}"
built="${BUILD_REPO_COMMIT:-${GITHUB_SHA:-$(version_field build_repo_commit)}}"
upstream="${upstream:-unknown}"
built="${built:-unknown}"

# The manifest is the committed one plus the identity of this build: the
# version number stays a counter, everything else says where the bytes came
# from.
node - "$manifest" "$stage/package.json" "$version" "$tag" "${revision:-0}" \
  "${zstd:-unknown}" "$emsdk" "$upstream" "$built" <<'NODE'
const [src, dst, version, tag, revision, zstd, emsdk, upstream, built] = process.argv.slice(2);
const pkg = require(src);
pkg.version = version;
pkg['7zip'] = {
  upstreamTag: tag,
  upstreamCommit: upstream,
  revision: Number(revision),
  zstd,
  emsdk,
  buildRepoCommit: built,
};
require('fs').writeFileSync(dst, JSON.stringify(pkg, null, 2) + '\n');
NODE

# --- verify the staged package before anything leaves the machine --------
[ "$(pkg_field "$stage/package.json" name)" = "$name" ] ||
  fail "$stage/package.json does not name $name"
[ "$(pkg_field "$stage/package.json" version)" = "$version" ] ||
  fail "$stage/package.json does not carry $version"

# npm publishes a package with a missing `files` entry without a word, and the
# result installs and then fails at runtime, so every entry is checked here.
while read -r entry; do
  [ -n "$entry" ] || continue
  [ -e "$stage/$entry" ] || fail "$stage/package.json lists $entry but there is no such file"
done < <(node -e "for (const f of require(process.argv[1]).files) console.log(f)" "$stage/package.json" && echo)

# The emcc output must parse as CommonJS; a broken rename would otherwise only
# ever surface for users.
node --check "$stage/7zz.cjs" || fail "$stage/7zz.cjs is not valid CommonJS"
# And the staged entry must resolve its own imports.
(cd "$stage" && node -e "import('./index.mjs').then(m => {
  if (typeof m.default !== 'function') { console.error('index.mjs does not default-export the factory'); process.exit(1); }
  if (typeof m.createApi !== 'function') { console.error('index.mjs does not export createApi'); process.exit(1); }
})") || fail "the staged package does not load"

# --- publish -------------------------------------------------------------
if $NPM view "$name@$version" version >/dev/null 2>&1; then
  printf 'skip  %s %s — already on the registry\n' "$name" "$version"
elif [ "$dry_run" = 1 ]; then
  printf 'would publish %s %s (from %s, staged in %s)\n' "$name" "$version" "$tag" "$stage"
else
  if [ -z "${NODE_AUTH_TOKEN:-}" ] && [ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ] &&
    ! grep -qs _authToken "$HOME/.npmrc"; then
    fail "no npm credentials: set NODE_AUTH_TOKEN, or grant the job id-token: write so npm can exchange an OIDC token, or put an authToken in ~/.npmrc"
  fi
  printf 'publishing %s %s (from %s)\n' "$name" "$version" "$tag"
  # shellcheck disable=SC2086 # NPM_PUBLISH_FLAGS is a word list on purpose
  (cd "$stage" && $NPM publish ${NPM_PUBLISH_FLAGS:-}) || fail "$NPM publish failed"
  printf 'done: %s %s\n' "$name" "$version"
fi
