# Scripts

`scripts/` contains helper automation used for local and CI validation workflows.

## Purpose

- Provides repeatable checks before changes are reconciled by Flux.
- Standardizes validation behavior across developer machines and pipelines.
- Reduces broken-manifest risk by enforcing schema and render checks.

## Current contents

- `validate.sh`: end-to-end repo validation workflow.

## Expected validation flow

The validation script is designed to:

1. Pull required schemas/dependencies for validation.
2. Lint YAML structure and basic consistency.
3. Validate cluster manifests against schemas.
4. Build kustomizations and validate rendered output.

## Usage guidance

- Run validation before pushing or opening a PR.
- Use the same tooling versions in CI where possible.
- Treat validation failures as blockers for promotion.

## See also

- [Repository root](../README.md)


## Parent/Siblings

- Parent: [Homelab Flux](../README.md)
- Siblings: [Apps](../apps/README.md); [Clusters](../clusters/README.md); [Infrastructure](../infrastructure/README.md).
