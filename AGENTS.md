# Repository Expectations

## Mission

- Help developers understand and optimize prompt caching behavior with reproducible experiments.
- Keep this repository cost-aware, deterministic, and easy to review.

## Build And Test

- Setup: `source ./setup.sh`
- Fast check:
  - `bash exp1-baseline.sh`
  - `bash exp2-cache-hit.sh`
- Full check (expensive):
  - `bash run-all.sh`

## Cost Safety

- Prefer fast checks first; avoid running the full suite unless needed.
- Be explicit in PRs when changes increase token usage, output size, or model count.
- Keep `README.md` cost disclaimer aligned with experiment behavior.

## Architecture Boundaries

- `exp*.sh` scripts orchestrate experiments and should stay deterministic.
- Parsing/metrics logic belongs in `analyze.py` and `compare.py`.
- Research/tutorial material belongs in `research/` and top-level documentation.
- Do not introduce hidden runtime dependencies without documenting them in `README.md` and `CONTRIBUTING.md`.

## Security Rules

- Never commit secrets, API keys, or sensitive prompt/tool output.
- Security reporting follows org policy: `AmadeusITGroup/.github/SECURITY.md`.
- Escalate edits touching `.github/`, ownership, or release/governance docs.

## Agent Workflow

- Read relevant files before editing; follow existing patterns.
- Prefer small, reviewable diffs with explicit rationale.
- Run deterministic local checks after changes.
- If you discover a repeated pitfall, propose a docs/check update.

## Review Expectations

- Include what changed, why, verification run, and residual risk.
- Keep changes scoped; avoid unrelated refactors.
