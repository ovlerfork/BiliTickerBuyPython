#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${CI:-}" && "${ALLOW_BRANCH_PUSH:-}" != "1" ]]; then
  echo "Refusing to push outside CI. Set ALLOW_BRANCH_PUSH=1 to override."
  exit 1
fi

root="$(git rev-parse --show-toplevel)"
upstream_remote="${UPSTREAM_REMOTE:-upstream}"
upstream_url="${UPSTREAM_URL:-https://github.com/mikumifa/biliTickerBuy.git}"
upstream_branch="${UPSTREAM_BRANCH:-main}"
origin_remote="${ORIGIN_REMOTE:-origin}"
main_ref="${MAIN_REF:-main}"
tmp_parent="${TMPDIR:-/tmp}"
worktree="$(mktemp -d "$tmp_parent/sync-main.XXXXXX")"

cleanup() {
  git -C "$root" worktree remove --force "$worktree" >/dev/null 2>&1 || rm -rf "$worktree"
}
trap cleanup EXIT

write_output() {
  local name="$1"
  local value="$2"

  echo "$name=$value"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "$name=$value" >>"$GITHUB_OUTPUT"
  fi
}

ensure_remotes() {
  if ! git -C "$root" remote get-url "$upstream_remote" >/dev/null 2>&1; then
    git -C "$root" remote add "$upstream_remote" "$upstream_url"
  fi

  git -C "$root" fetch --tags "$upstream_remote" "+refs/heads/$upstream_branch:refs/remotes/$upstream_remote/$upstream_branch"

  if git -C "$root" remote get-url "$origin_remote" >/dev/null 2>&1; then
    git -C "$root" fetch --tags "$origin_remote" "+refs/heads/$main_ref:refs/remotes/$origin_remote/$main_ref" || true
  fi
}

find_python() {
  if [[ -n "${PYTHON:-}" ]]; then
    echo "$PYTHON"
  elif command -v python3 >/dev/null 2>&1; then
    echo python3
  elif command -v python >/dev/null 2>&1; then
    echo python
  else
    echo "Python 3.11+ is required to read pyproject.toml." >&2
    exit 1
  fi
}

read_version_from_ref() {
  local ref="$1"
  local python_bin="$2"

  git -C "$root" show "$ref:pyproject.toml" |
    "$python_bin" -c 'import sys, tomllib; print(tomllib.load(sys.stdin.buffer)["project"]["version"])'
}

commit_if_needed() {
  if git -C "$worktree" diff --cached --quiet; then
    return
  fi

  git -C "$worktree" \
    -c user.name="${GIT_AUTHOR_NAME:-patch automation}" \
    -c user.email="${GIT_AUTHOR_EMAIL:-patch-automation@example.invalid}" \
    commit -m "chore: remove GitHub workflows from upstream sync"
}

ensure_remotes

upstream_ref="refs/remotes/$upstream_remote/$upstream_branch"
origin_main_ref="refs/remotes/$origin_remote/$main_ref"
python_bin="$(find_python)"
new_version="$(read_version_from_ref "$upstream_ref" "$python_bin")"
old_version=""
if git -C "$root" show-ref --verify --quiet "$origin_main_ref"; then
  old_version="$(read_version_from_ref "$origin_main_ref" "$python_bin" || true)"
fi

git -C "$root" worktree add --detach "$worktree" "$upstream_ref"

if [[ -d "$worktree/.github/workflows" ]] || git -C "$worktree" ls-files --error-unmatch .github/workflows >/dev/null 2>&1; then
  rm -rf "$worktree/.github/workflows"
  git -C "$worktree" add -A -- .github/workflows
  commit_if_needed
fi

if git -C "$root" show-ref --verify --quiet "$origin_main_ref" &&
  git -C "$worktree" diff --quiet "$origin_main_ref" HEAD; then
  main_changed=false
else
  main_changed=true
fi

if [[ "$old_version" != "$new_version" ]]; then
  version_changed=true
else
  version_changed=false
fi

write_output main_changed "$main_changed"
write_output version_changed "$version_changed"
write_output old_version "$old_version"
write_output new_version "$new_version"

if [[ "$main_changed" == "true" ]]; then
  git -C "$worktree" push --force-with-lease "$origin_remote" "HEAD:$main_ref"
else
  echo "$main_ref already matches sanitized $upstream_remote/$upstream_branch."
fi
