---
name: bilitickerbuy-patched-fork
description: "Operate this BiliTickerBuy fork's patch-based workflow. Use when starting feature work, converting local branches into patch files, refreshing existing patches, running local patch checks, or handling the dev/main/latest branch model where generated branches remove .github/workflows before push."
---

# BiliTickerBuy Patch Fork

This repo uses `dev` as the control branch. It owns patch files, support scripts, Actions, release docs, and repo-local skills. `main` tracks upstream with `.github/workflows` removed before push. `latest` is generated from `main` plus patches, also with `.github/workflows` removed before push.

## Start Feature Work

Start implementation branches from upstream-like `main`, not `dev` or `latest`:

```bash
git fetch origin main dev --prune
git switch main
git pull --ff-only origin main
git switch -c <feature-branch>
```

Keep the branch focused on the product change. Do not edit patch-management docs, scripts, or workflows from the feature branch unless that is the feature.

## Convert a Branch to Patches

Use this when a working branch such as `proxy-disable-direct` should become one or more patch files.

1. Inspect the branch diff against `main` and split it by logical topic.
2. Create a temporary stack from `main`.
3. Cherry-pick, reset, or manually replay each topic into one commit per patch.
4. Export patches with stable formatting.
5. Switch to `dev`, place the patch files under the repo's patch directory, update patch docs if they exist, and run checks.

Example:

```bash
git fetch origin main dev --prune
git switch -c patch-stack origin/main
git cherry-pick <commit-range-or-shas>
git reset --soft origin/main
git commit -m "proxy: disable direct connection fallback"
git format-patch --zero-commit --no-signature --no-stat -o /tmp/btb-patches origin/main..HEAD
git switch dev
cp /tmp/btb-patches/*.patch patches/cur/
```

If the branch contains unrelated changes, make multiple stack commits and export multiple patches in dependency order. Prefer patch filenames with ordering gaps, for example `0010-proxy-disable-direct.patch`.

## Update an Existing Patch

Rebuild the patch from `main` instead of editing hunks by hand unless the fix is trivial:

```bash
git fetch origin main dev --prune
git switch -c refresh-<patch-name> origin/main
git am --3way patches/cur/<patch-file>
# resolve conflicts or make the intended edits
git add <changed-files>
git commit --amend --no-edit
git format-patch --zero-commit --no-signature --no-stat -1 HEAD -o /tmp/btb-refresh
git switch dev
cp /tmp/btb-refresh/*.patch patches/cur/<patch-file>
```

After refreshing, reapply the full patch set from a clean `main` checkout to catch ordering issues.

## Local Checks

Prefer repo scripts when present:

```bash
scripts/check-patches.sh
```

If the scripts are not available in the checkout, run the closest direct checks:

```bash
uv sync --dev
uv run pytest
uv run ruff format --check .
uv run ruff check .
```

For release or CI changes, also verify the generated branch rule locally: after patches are applied, `.github/workflows` must be removed before pushing `main` or `latest`.

## Generated Branch Workflow Rule

Patch files may include `.github` changes because `dev` owns CI. Generated `main` and `latest` must not publish workflow files:

```bash
rm -rf .github/workflows
```

Run that deletion after applying patches and before pushing generated branches. Do not "fix" generated `latest` by committing to it directly; refresh the responsible patch on `dev` and regenerate.
