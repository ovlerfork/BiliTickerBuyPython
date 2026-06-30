#!/usr/bin/env bash
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
origin_remote="${ORIGIN_REMOTE:-origin}"
default_base_ref() {
  if [[ -n "${CI:-}" ]]; then
    echo "$origin_remote/main"
  else
    echo main
  fi
}

base_ref="${PATCH_BASE_REF:-$(default_base_ref)}"
tmp_parent="${TMPDIR:-/tmp}"
worktree="$(mktemp -d "$tmp_parent/check-patches.XXXXXX")"

cleanup() {
  git -C "$root" worktree remove --force "$worktree" >/dev/null 2>&1 || rm -rf "$worktree"
}
trap cleanup EXIT

fetch_base_ref() {
  if [[ "$base_ref" == "$origin_remote/"* ]] && git -C "$root" remote get-url "$origin_remote" >/dev/null 2>&1; then
    local branch="${base_ref#"$origin_remote"/}"
    git -C "$root" fetch --tags "$origin_remote" "+refs/heads/$branch:refs/remotes/$origin_remote/$branch"
  fi
}

apply_patchset() {
  local patch_dir="$root/patches/cur"

  if [[ ! -d "$patch_dir" ]]; then
    echo "No patch directory: $patch_dir"
    return 0
  fi

  shopt -s nullglob
  local patches=("$patch_dir"/*.patch)
  shopt -u nullglob

  if (( ${#patches[@]} == 0 )); then
    echo "No patches to apply."
    return 0
  fi

  if ! git -C "$worktree" am --3way "${patches[@]}"; then
    echo
    echo "Patch apply failed against $base_ref."
    echo
    git -C "$worktree" status --short
    local conflicts
    conflicts="$(git -C "$worktree" diff --name-only --diff-filter=U || true)"
    if [[ -n "$conflicts" ]]; then
      echo
      echo "Conflicted files:"
      echo "$conflicts"
    fi
    return 1
  fi
}

run_if_available() {
  local tool="$1"
  shift

  if command -v "$tool" >/dev/null 2>&1; then
    "$tool" "$@"
    return
  fi

  if command -v uv >/dev/null 2>&1 && uv run --no-sync --frozen "$tool" --version >/dev/null 2>&1; then
    uv run --no-sync --frozen "$tool" "$@"
    return
  fi

  echo "Skipping $tool; it is not available."
}

fetch_base_ref
git -C "$root" worktree add --detach "$worktree" "$base_ref"
apply_patchset
rm -rf "$worktree/.github/workflows"

cd "$worktree"
run_if_available ruff check .
run_if_available ruff format --check .
run_if_available pytest
