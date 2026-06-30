# Architecture Notes For Humans And Agents

## System Overview

This repository is organized into three main layers:

1. **Experiment orchestration** — shell scripts (`exp*.sh`, `run-all.sh`, `run-multi-model.sh`, `setup.sh`)
2. **Analysis/reporting** — Python tools (`analyze.py`, `compare.py`, `exp17-semantic-threshold-simulation.py`)
3. **Documentation/research** — tutorial and research corpus (`README.md`, `tutorial-plan.md`, `research/`)

## Module Boundaries

| Area | Owns | Public interface | Must not depend on |
|---|---|---|---|
| `exp*.sh` + runners | Experiment execution flow and reproducible run order | `bash <script>.sh` | Internal Python implementation details beyond documented CLI arguments |
| `analyze.py` | OTel parsing and per-run cache metrics | `python3 analyze.py <otel-jsonl>` | Ad-hoc parsing duplicated inside shell scripts |
| `compare.py` | Cross-experiment comparison and pricing estimates | `python3 compare.py <otel-dir> [--pricing <json>]` | Hidden network/runtime assumptions not documented in README |
| `research/`, docs | Educational narrative, references, best practices | Markdown docs | Runtime behavior assumptions that contradict scripts |

## Deterministic Verification Contract

Low-cost local checks:

- `bash -n *.sh`
- `python -m py_compile analyze.py compare.py exp17-semantic-threshold-simulation.py`

Higher-cost functional checks:

- `source ./setup.sh`
- `bash exp1-baseline.sh`
- `bash exp2-cache-hit.sh`

## Change Guidance

- Keep experiment scripts deterministic and explicit in assumptions.
- Keep cost-impacting changes documented in `README.md` and `CONTRIBUTING.md`.
- Any new experiment should include clear expected outcomes and analysis compatibility.
