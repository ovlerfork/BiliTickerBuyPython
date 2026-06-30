#!/usr/bin/env bash
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
pyproject="${1:-${PYPROJECT_FILE:-$root/pyproject.toml}}"
remote="${PATCH_TAG_REMOTE:-origin}"

if [[ -n "${PYTHON:-}" ]]; then
  python_bin="$PYTHON"
elif command -v python3 >/dev/null 2>&1; then
  python_bin="python3"
elif command -v python >/dev/null 2>&1; then
  python_bin="python"
else
  echo "Python 3.11+ is required to read pyproject.toml." >&2
  exit 1
fi

version="$(
  "$python_bin" - "$pyproject" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as fh:
    data = tomllib.load(fh)

print(data["project"]["version"])
PY
)"

prefix="v${version}-patch"
tags="$(
  {
    git -C "$root" tag -l "${prefix}*"
    git -C "$root" ls-remote --tags "$remote" "${prefix}*" 2>/dev/null | awk '{print $2}' | sed 's#refs/tags/##; s#\^{}##'
  } | sort -u
)"

last_number="$(
  printf '%s\n' "$tags" |
    sed -n "s/^${prefix}\([0-9][0-9]*\)$/\1/p" |
    sort -n |
    tail -1
)"

patch_number="$(( ${last_number:-0} + 1 ))"
patch_tag="${prefix}${patch_number}"
if (( patch_number == 1 )); then
  prerelease=false
else
  prerelease=true
fi

if [[ -n "${DOCKER_IMAGE:-}" ]]; then
  docker_image="$DOCKER_IMAGE"
elif [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
  docker_image="ghcr.io/${GITHUB_REPOSITORY,,}"
else
  docker_image="ghcr.io/ovlerfork/bilitickerbuypython"
fi

shell_quote() {
  printf '%q' "$1"
}

emit_assignment() {
  local name="$1"
  local value="$2"
  printf '%s=%s\n' "$name" "$(shell_quote "$value")"
}

emit_assignment PATCH_BASE_VERSION "$version"
emit_assignment PATCH_NUMBER "$patch_number"
emit_assignment PATCH_TAG "$patch_tag"
emit_assignment PATCH_IS_PRERELEASE "$prerelease"
emit_assignment DOCKER_IMAGE "$docker_image"
emit_assignment DOCKER_TAG_EXACT "$docker_image:$patch_tag"
emit_assignment DOCKER_TAG_ROLLING "$docker_image:patch"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "patch_base_version=$version"
    echo "patch_number=$patch_number"
    echo "patch_tag=$patch_tag"
    echo "prerelease=$prerelease"
    echo "docker_image=$docker_image"
    echo "docker_tag_exact=$docker_image:$patch_tag"
    echo "docker_tag_rolling=$docker_image:patch"
  } >>"$GITHUB_OUTPUT"
fi
