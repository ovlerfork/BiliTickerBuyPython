#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${CI:-}" && "${ALLOW_BRANCH_PUSH:-}" != "1" ]]; then
  echo "Refusing to push branches or tags outside CI. Set ALLOW_BRANCH_PUSH=1 to override."
  exit 1
fi

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
worktree="$(mktemp -d "$tmp_parent/publish-latest.XXXXXX")"

cleanup() {
  git -C "$root" worktree remove --force "$worktree" >/dev/null 2>&1 || rm -rf "$worktree"
}
trap cleanup EXIT

fetch_base_ref() {
  if git -C "$root" remote get-url "$origin_remote" >/dev/null 2>&1; then
    git -C "$root" fetch --tags "$origin_remote"
  fi

  if [[ "$base_ref" == "$origin_remote/"* ]] && git -C "$root" remote get-url "$origin_remote" >/dev/null 2>&1; then
    local branch="${base_ref#"$origin_remote"/}"
    git -C "$root" fetch "$origin_remote" "+refs/heads/$branch:refs/remotes/$origin_remote/$branch"
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

commit_if_needed() {
  if git -C "$worktree" diff --cached --quiet; then
    return
  fi

  git -C "$worktree" \
    -c user.name="${GIT_AUTHOR_NAME:-patch automation}" \
    -c user.email="${GIT_AUTHOR_EMAIL:-patch-automation@example.invalid}" \
    commit -m "chore: remove GitHub workflows from latest"
}

create_github_release() {
  local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

  if [[ -z "$token" ]]; then
    echo "Skipping GitHub Release; GH_TOKEN/GITHUB_TOKEN is not set."
    return
  fi

  if ! command -v gh >/dev/null 2>&1; then
    echo "Skipping GitHub Release; gh is not available."
    return
  fi

  export GH_TOKEN="$token"

  if gh release view "$PATCH_TAG" >/dev/null 2>&1; then
    echo "GitHub Release $PATCH_TAG already exists; skipping create."
    return
  fi

  local args=(release create "$PATCH_TAG" --title "$PATCH_TAG" --notes-file "$release_notes_file")
  if [[ "$PATCH_IS_PRERELEASE" == "true" ]]; then
    args+=(--prerelease)
  fi

  gh "${args[@]}"
}

fetch_base_ref
git -C "$root" worktree add --detach "$worktree" "$base_ref"
git -C "$worktree" config user.name "${GIT_AUTHOR_NAME:-patch automation}"
git -C "$worktree" config user.email "${GIT_AUTHOR_EMAIL:-patch-automation@example.invalid}"
base_commit="$(git -C "$worktree" rev-parse --short HEAD)"
apply_patchset

if [[ -d "$worktree/.github/workflows" ]] || git -C "$worktree" ls-files --error-unmatch .github/workflows >/dev/null 2>&1; then
  rm -rf "$worktree/.github/workflows"
  git -C "$worktree" add -A -- .github/workflows
  commit_if_needed
fi

eval "$("$root/scripts/detect-patch-version.sh" "$worktree/pyproject.toml")"

release_notes_file="${RELEASE_NOTES_FILE:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/patch-release-notes.md}"
mkdir -p "$(dirname "$release_notes_file")"
{
  echo "$PATCH_TAG"
  echo
  echo "Base: $base_ref ($base_commit)"
  echo
  echo "Patches applied:"
  shopt -s nullglob
  patch_names=("$root"/patches/cur/*.patch)
  shopt -u nullglob
  if (( ${#patch_names[@]} == 0 )); then
    echo "- none"
  else
    for patch in "${patch_names[@]}"; do
      echo "- $(basename "$patch")"
    done
  fi
  echo
  echo "Docker tags:"
  echo "- $DOCKER_TAG_EXACT"
  echo "- $DOCKER_TAG_ROLLING"
} >"$release_notes_file"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "release_notes_file=$release_notes_file"
    echo "patch_base_version=$PATCH_BASE_VERSION"
    echo "patch_tag=$PATCH_TAG"
    echo "patch_number=$PATCH_NUMBER"
    echo "prerelease=$PATCH_IS_PRERELEASE"
    echo "docker_tag_exact=$DOCKER_TAG_EXACT"
    echo "docker_tag_rolling=$DOCKER_TAG_ROLLING"
  } >>"$GITHUB_OUTPUT"
fi

git -C "$worktree" tag "$PATCH_TAG"
git -C "$worktree" push --atomic --force-with-lease "$origin_remote" HEAD:refs/heads/latest "refs/tags/$PATCH_TAG"
create_github_release

echo "Published latest and $PATCH_TAG"
echo "Release notes: $release_notes_file"
