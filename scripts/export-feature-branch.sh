#!/usr/bin/env bash
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
base_ref="${PATCH_BASE_REF:-main}"
out_dir="${PATCH_OUTPUT_DIR:-$root/patches/cur}"

mkdir -p "$out_dir"

shopt -s nullglob
existing=("$out_dir"/*.patch)
shopt -u nullglob

if (( ${#existing[@]} > 0 )) && [[ "${FORCE:-}" != "1" ]]; then
  echo "Refusing to overwrite existing patches in $out_dir. Set FORCE=1 to replace them."
  exit 1
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/export-patches.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

if git -C "$root" diff --quiet "$base_ref..HEAD"; then
  echo "No changes to export from $base_ref..HEAD."
  exit 1
fi

git -C "$root" format-patch \
  --zero-commit \
  --no-signature \
  --no-stat \
  -o "$tmp_dir" \
  "$base_ref..HEAD"

if [[ "${FORCE:-}" == "1" ]]; then
  rm -f "$out_dir"/*.patch
fi

shopt -s nullglob
new_patches=("$tmp_dir"/*.patch)
shopt -u nullglob

if (( ${#new_patches[@]} == 0 )); then
  echo "No patch files were generated."
  exit 1
fi

cp "${new_patches[@]}" "$out_dir/"
echo "Exported ${#new_patches[@]} patch file(s) to $out_dir."
