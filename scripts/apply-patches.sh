#!/usr/bin/env bash
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
patch_dir="${PATCH_DIR:-$root/patches/cur}"

if [[ ! -d "$patch_dir" ]]; then
  echo "No patch directory: $patch_dir"
  exit 0
fi

shopt -s nullglob
patches=("$patch_dir"/*.patch)
shopt -u nullglob

if (( ${#patches[@]} == 0 )); then
  echo "No patches to apply."
  exit 0
fi

cd "$root"

if ! git am --3way "${patches[@]}"; then
  echo
  echo "Patch apply failed. Resolve the conflict, then run git am --continue, or abort with git am --abort."
  echo
  git status --short
  conflicts="$(git diff --name-only --diff-filter=U || true)"
  if [[ -n "$conflicts" ]]; then
    echo
    echo "Conflicted files:"
    echo "$conflicts"
  fi
  exit 1
fi
