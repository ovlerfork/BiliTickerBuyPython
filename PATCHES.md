# Patch Workflow

This fork keeps `dev` as the control/default branch. Patch files, scripts, docs, and fork-only automation live there.

Branch roles:

- `dev`: human-maintained control branch.
- `main`: upstream `main` with `.github/workflows` removed before pushing to this fork.
- `latest`: generated branch: `main` plus `patches/cur/*.patch`, with `.github/workflows` removed before pushing.

Patch files live in `patches/cur/` and are applied in filename order with `git am --3way`.

Common commands:

```bash
scripts/apply-patches.sh
scripts/check-patches.sh
PATCH_BASE_REF=main scripts/check-patches.sh
```

To convert a feature branch based on `main` into patch files:

```bash
scripts/export-feature-branch.sh
```

If `patches/cur` already has patch files, the export script stops instead of overwriting them. Use `FORCE=1 scripts/export-feature-branch.sh` only when replacing the current patchset is intended.

When upstream changes conflict with local patches, repair the patch on a temporary branch based on the new `main`, export the updated patch files, then validate with `scripts/check-patches.sh`.
