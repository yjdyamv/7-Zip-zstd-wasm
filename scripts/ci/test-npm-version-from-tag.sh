#!/bin/bash
# test-npm-version-from-tag.sh — the tag -> npm version mapping is a rule, so
# it gets tests. Run from the repo root: bash scripts/ci/test-npm-version-from-tag.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/npm-version-from-tag.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
check() {
  local desc="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then
    pass=$((pass + 1))
    printf 'PASS %s\n' "$desc"
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n     want: %s\n     got:  %s\n' "$desc" "$want" "$got"
  fi
}

map_tag() { # map_tag <tag> [versions...]
  local tag="$1"
  shift
  if [ "$#" -gt 0 ]; then
    printf '%s\n' "$@" >"$tmp/versions.json"
    bash "$script" "$tag" "$tmp/versions.json"
  else
    bash "$script" "$tag"
  fi
}

# First publish of a 7-Zip line: the counter starts at 0.
check "26.05 first publish" "26.5.0" "$(map_tag v26.05-v1.5.7-R1)"
check "refs/tags prefix is accepted" "26.5.0" "$(map_tag refs/tags/v26.05-v1.5.7-R1)"
check "leading zeros are decimal" "25.1.0" "$(map_tag v25.01-v1.5.7-R4)"

# Same 7-Zip line again — an upstream R bump and a rebuild of our own both
# consume the next counter value.
check "same line, next counter" "26.5.1" "$(map_tag v26.05-v1.5.7-R1 '["26.5.0"]')"
check "same line, counter after several" "26.5.4" \
  "$(map_tag v26.05-v1.5.8-R1 '["26.5.0","26.5.1","26.5.2","26.5.3"]')"
check "newer 7-Zip line starts at 0" "26.6.0" "$(map_tag v26.06-v1.5.8-R1 '["26.5.0","26.5.1"]')"

# The clamp: upstream publishing an older line later must not move `latest`
# backwards. The tag is recorded in metadata; the version stays above newest.
check "older line published late is clamped" "26.5.3" \
  "$(map_tag v26.02-v1.5.7-R2 '["26.5.0","26.5.2"]')"
check "clamp uses the newest line's patch" "26.6.2" \
  "$(map_tag v25.01-v1.5.7-R4 '["26.5.0","26.6.0","26.6.1"]')"

# Registry noise must not be mistaken for our own versions.
check "dist-tag names are ignored" "26.5.1" \
  "$(map_tag v26.05-v1.5.7-R1 '["latest","next","26.5.0"]')"

# Bad tags fail loudly instead of inventing a version.
if bash "$script" "nightly" >/dev/null 2>&1; then
  fail=$((fail + 1))
  printf 'FAIL a tag without a 7-Zip version must be rejected\n'
else
  pass=$((pass + 1))
  printf 'PASS a tag without a 7-Zip version must be rejected\n'
fi
if bash "$script" >/dev/null 2>&1; then
  fail=$((fail + 1))
  printf 'FAIL the tag is required\n'
else
  pass=$((pass + 1))
  printf 'PASS the tag is required\n'
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
