#!/bin/bash
# npm-version-from-tag.sh — map an upstream tag to an npm version
#
#   v26.05-v1.5.7-R1   -> 26.5.0
#   same 7-Zip line again -> 26.5.1, 26.5.2, ...
#   v26.06-v1.5.8-R1   -> 26.6.0
#
# The npm version is `<7-Zip major>.<7-Zip minor>.<publish counter>`. The counter
# is per 7-Zip line and is consumed by every publish of that line, whether the
# build came from a new upstream tag or from a rebuild of our own. Upstream's
# exact identity (tag, zstd version, R counter, commit) is recorded in the
# package's `7zip` field and in VERSION, never in the version number.
#
# Why the counter and not the R number: an R bump is only one reason to
# publish. A rebuild (patched source, newer emsdk) has to get its own number,
# and if R had claimed them the next real R would collide.
#
# Why "never go backwards": upstream can publish a revision for an older 7-Zip
# line after a newer line already shipped (v26.02-...-R2 exists next to
# v26.05-...-R1). Mapping that naively yields a version below `latest`, so the
# computed version is clamped to just above the newest published one.
#
# Usage:
#   npm-version-from-tag.sh <tag> [existing-versions-file]
#
# Without a versions file the counter starts at 0 (first publish of the line).
# The file is one version per line, e.g. the output of `npm view <pkg> versions`
# with the punctuation stripped, or just the JSON array it prints.
set -euo pipefail

die() {
  printf '%s\n' "error: $*" >&2
  exit 1
}

tag="${1:-}"
[ -n "$tag" ] || die "usage: $0 <tag> [existing-versions-file]"
versions_file="${2:-}"

# Accept refs/tags/... and a leading "v".
tag="${tag#refs/tags/}"
tag="${tag#v}"

# The 7-Zip version is the leading number pair; the rest of the tag describes
# the codec bundles and the revision, which do not belong in the version.
case "$tag" in
  [0-9]*.[0-9]*) ;;
  *) die "tag '$1' does not start with a <major>.<minor> 7-Zip version" ;;
esac
major="${tag%%.*}"
rest="${tag#*.}"
# "05-v1.5.7-R1" -> "05": the minor ends at the first non-digit.
minor="${rest%%[!0-9]*}"
case "$minor" in
  '' | *[!0-9]*) die "tag '$1' has a non-numeric minor version" ;;
esac
# "26.05" and "25.01" are decimal in upstream's naming, so 10# keeps bash from
# reading a leading zero as octal.
major=$((10#$major))
minor=$((10#$minor))

line="$major.$minor"

newest=""
if [ -n "$versions_file" ]; then
  [ -r "$versions_file" ] || die "cannot read $versions_file"
  # Keep only plain x.y.z entries: dist-tags and prereleases are not ours.
  newest="$(tr -c '0-9.\n' '\n' <"$versions_file" |
    grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' |
    sort -t. -k1,1n -k2,2n -k3,3n |
    tail -1 || true)"
fi

patch=0
if [ -n "$newest" ]; then
  newest_line="${newest%.*}"
  newest_patch="${newest##*.}"
  if [ "$newest_line" = "$line" ]; then
    patch=$((newest_patch + 1))
  elif [ "$major" -lt "${newest_line%%.*}" ] ||
    { [ "$major" -eq "${newest_line%%.*}" ] && [ "$minor" -lt "${newest_line##*.}" ]; }; then
    # The tag belongs to a 7-Zip line older than what is already published.
    # Publishing it would move `latest` backwards, so number it inside the
    # newest line instead and leave the tag in the metadata.
    line="$newest_line"
    patch=$((newest_patch + 1))
  fi
fi

printf '%s\n' "$line.$patch"
