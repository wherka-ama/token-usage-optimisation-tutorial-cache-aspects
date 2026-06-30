# Releasing

This repository follows Semantic Versioning (`MAJOR.MINOR.PATCH`).

## Versioning Policy

- `PATCH`: docs clarifications, non-breaking script/reporting fixes.
- `MINOR`: new experiments, new analysis dimensions, additive features.
- `MAJOR`: breaking changes in script interfaces, output contracts, or project structure.

## Release Process

1. Ensure `main` is green and up to date.
2. Update `CHANGELOG.md`:
   - Move relevant entries from `[Unreleased]` to a new version section.
3. Choose next SemVer version.
4. Create annotated tag:
   - `vX.Y.Z`
5. Publish GitHub release from the tag with summary notes.
6. Start next cycle by keeping `[Unreleased]` section present.

## Release Cadence

- No fixed calendar cadence.
- Releases are created when meaningful grouped changes are ready.
