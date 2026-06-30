# Contributing to Token Usage Optimisation Tutorial (Cache Aspects)

Thanks for helping improve this tutorial and experiment harness.

## Code of Conduct

This repository follows the organization-wide code of conduct from `AmadeusITGroup/.github`.

## Before You Start

1. Search existing issues and pull requests to avoid duplication.
2. For non-trivial changes, open an issue first to align on scope.
3. Keep changes focused and reproducible.

## Development Setup

### Prerequisites

- Bash (Linux/macOS)
- Python 3.10+
- GitHub Copilot CLI (authenticated)

### Local setup

1. Clone and enter the repository.
2. Run:
   - `source ./setup.sh`
3. Validate with one experiment:
   - `bash exp1-baseline.sh`

## Types of Contributions

- Fix experiment scripts
- Improve analytics (`analyze.py`, `compare.py`)
- Improve docs/tutorial flow
- Add new reproducible cache experiments

## Style and Quality

- Keep scripts deterministic and idempotent where possible.
- Prefer explicit comments for experimental assumptions.
- Keep docs aligned with actual script behavior.
- For Python, keep changes simple, typed where helpful, and readable.

## Testing Your Changes

Before opening a PR, run:

- `bash exp1-baseline.sh`
- `bash exp2-cache-hit.sh`
- `python3 analyze.py "$HOME/cache-experiments/otel/exp2-cache-hit-*.jsonl"`

If you changed reporting logic, also run:

- `bash run-all.sh`

## Pull Request Process

1. Create a branch from `main`.
2. Use clear commit messages (Conventional Commits preferred).
3. Open a PR using the repository PR template.
4. Ensure checks pass and address reviewer feedback.

## Reporting Bugs

Please include:

- What you ran (exact script/command)
- Expected vs actual behavior
- Relevant logs/output snippets
- OS/runtime info

## Security

For vulnerability reporting, use the organization-level security process defined in `AmadeusITGroup/.github/SECURITY.md`.

## Maintainers

- `@wherka-ama`
- `@micheliknechtel`
