# Changelog

All notable changes to VIGIL are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). For a methodology spec, "breaking" means any change to phase contracts or JSON schemas that requires existing implementations to be updated.

---

## [Unreleased]

_Nothing yet._

## [1.0.1] — 2026-04-23 — EIIS-1.0 conformance

### Changed

- **`install.sh`** — Full EIIS-1.0 §3 interface: `--target DIR`, `--hosts LIST`, `--force`, `--dry-run`, `--non-interactive`, `--manifest-only`, `--version`, `--shared-dispatch`/`--no-shared-dispatch`, `-h/--help`. Legacy positional target preserved with deprecation warning; existing `--mode=VALUE` and `--mode VALUE` both accepted. Emits `install.manifest.json` with token budget, hosts wired, handoffs declared, security posture, and authority mode. Writes per-host dispatch files for claude-code (`.claude/agents/vigil.md`), cursor (`.cursor/rules/vigil.mdc`), and opencode (`.opencode/agents/vigil.md`). Idempotency check: non-interactive mode exits 3 on existing manifest without `--force`.
- **Version footers** — synchronized across AGENTS.md, README.md, CLAUDE.md, VIGIL.md, DESIGN-RATIONALE.md, agent.md, all four host wirings, all four templates, and canary missions from 1.0.0 → 1.0.1.

### Unchanged

- FORGE cycle (Verify → Isolate → Graph → Intervene → Learn)
- Ten architectural invariants, eleven-category failure taxonomy
- Five phase skills, four decision templates, three JSON schemas
- Per-project `.vigil/config.yml` generation and memory ledger bootstrap

## [1.0.0] — 2026-04-16

Initial release of the VIGIL methodology — forensic debugger for code failures.

### Added

- **agent.md** — always-loaded entry point (~900 tokens) with identity, P0 invariants, skill-loading triggers, and team-wide structural markers.
- **VIGIL.md** — authoritative methodology specification covering all five phases (Verify, Isolate, Graph, Intervene, Learn), ten architectural invariants, eleven-category failure taxonomy, and six portable abstractions.
- **AGENTS.md** — agents.md open-standard compliant rules file for Copilot, Cursor, OpenCode hosts.
- **CLAUDE.md** — Claude Code entry pointer.
- **skills/** — five progressive-disclosure phase skills:
  - `verify/SKILL.md` — deterministic-first reproduction protocol, statistical switch on two-failure threshold, Wilson 95% CI for small-N flakes
  - `isolate/SKILL.md` — delta-debugging-style reduction with category-specific techniques (git bisect, dep walk, contract comparison, timing differential); ruled-out trail as first-class output
  - `graph/SKILL.md` — Information Dependency Graph construction, symptom/root discrimination, graph-shape handling (cyclic, disconnected, single-node)
  - `intervene/SKILL.md` — counterfactual replay protocol, ≥3-hypothesis plurality rule, 5-intervention hard cap, authority-gated execution, statistical-mode flip threshold (4/5)
  - `learn/SKILL.md` — finding emission with ATLAS-compatible schema, walk-back to originating decision, failure-signature memory with de-duplication, routing to downstream Eidolon
- **templates/** — four artifact skeletons:
  - `root-cause-report.md` — primary deliverable (~1,150 tokens)
  - `verified-patch.md` — conditional patch artifact when authority permits
  - `failure-signature.md` — memory ledger entry with de-duplication scoring
  - `escalation-brief.md` — budget-exhausted path with "what evidence would resolve this" section
- **schemas/** — three JSON Schema v2020-12 validators:
  - `reproduction.v1.json` — Phase V output; enforces ≥2 runs, statistical evidence on flaky verdict, GAP marker on intermittent
  - `intervention-log.v1.json` — Phase Intervene output; enforces ≥3 hypotheses, ≤5 interventions, null-survivor implies escalation
  - `root-cause-report.v1.json` — Phase L primary output; rejects L-confidence for root-cause emission, enforces SPEC_DEFECT→SPECTRA routing
- **hosts/** — per-host wiring documentation for Claude Code, Cursor, GitHub Copilot, OpenCode.
- **DESIGN-RATIONALE.md** — exhaustive mapping from every non-obvious design decision to its research basis (GraphTracer, AgenTracer, CHIEF, Lifecycle of Failures, Delta Debugging, TALE, CorrectBench, SWE-bench+, OpenTelemetry GenAI).
- **install.sh** — idempotent installer with `--mode` (read-only|sandbox|write), `--force`, per-project config generation, memory ledger initialization.
- **evals/canary/missions.md** — 23-mission evaluation dataset:
  - 15 deterministic missions (target ≥80% pass rate) covering all non-flake failure categories, three entry modes, confirmation-bias trap, plurality enforcement
  - 8 non-deterministic missions (target ≥65% pass rate) covering heisenbugs, CI-only flakes, external-dep flakes, concurrent writes, statistical edge cases
- **README.md** — architecture overview, quick start, team integration, research foundation.

### Architectural Invariants (v1.0)

1. Reproduction gates attribution
2. Dependency graph, not temporal sequence
3. Hypothesis plurality (≥3 before intervention)
4. Counterfactual gates blame
5. Bounded intervention budget (5 hard max)
6. Flag-gated authority
7. Evidence-anchored findings
8. Non-determinism declared, not masked
9. Sandbox adapter interface (pluggable)
10. Telemetry-driven compaction

### Handoff Contracts (v1.0)

- `APIVR-Δ → VIGIL` (escalation mode): consumes `repair-failed-report.md` + session log + delta history
- `VIGIL → APIVR-Δ`: emits `root-cause-report.md` + optional `verified-patch.diff` for surgical fixes
- `VIGIL → SPECTRA`: emits `root-cause-report.md` for systemic issues (SPEC_DEFECT, COMPOUND, structural drift)
- `VIGIL → IDG`: emits `root-cause-report.md` + session log for incident chronicling
- `VIGIL → FORGE`: emits `escalation-brief.md` when 5-intervention budget exhausts on ambiguity
- `VIGIL → human`: emits `escalation-brief.md` for environment errors, safety-critical judgments, or unreproducible failures

### Known Limitations

- **Non-determinism attribution is a genuinely open research area.** The 4/5 flip threshold in statistical mode is heuristic, not principled. Future iterations may refine this as research matures.
- **IDG construction cost is not yet benchmarked.** Building the dependency graph from trace evidence costs tokens. An ablation study on minimum trace granularity is in the research backlog.
- **Compound-failure handling emits multiple findings** but does not yet construct a unified causal-graph-with-multiple-roots (CHIEF-style). This is a candidate for v1.1 or v2.0 depending on evaluation results.
- **Oracle validation is single-source.** When the "correct" oracle value for counterfactual replay is itself uncertain (spec ambiguity), attribution currently requires `[DISPUTED]` marker and escalation. Multi-oracle validation is an open design question.
- **Meta-debugging is not supported.** If VIGIL's own mission fails, the current design escalates to human. Recursive self-diagnosis was explicitly rejected per D5 (Bounded Self-Correction).

### Token Budget

- Entry point: ~877 tokens (under 1,000-token cap)
- Individual skills: 1,056–1,760 tokens
- Typical working set (entry + skill + template): ~3,100 tokens (under 3,500 specialist cap)

---

## Versioning Policy

- **Major bump (v2.0.0)**: Changes to invariants (I-1 through I-10). Existing implementations must update fundamentally.
- **Minor bump (v1.1.0)**: Changes to phase contracts, JSON schemas, or failure taxonomy. Implementations must update artifacts but core logic unchanged.
- **Patch bump (v1.0.1)**: Clarifications, typos, additional canary missions, rationale expansions. No implementation changes required.

Implementations declare `methodology_version: "1.0"` in their `agent.md` frontmatter and MUST fail fast on a detected version mismatch with their loaded VIGIL spec.

---

*VIGIL v1.0.1 — Verify · Isolate · Graph · Intervene · Learn*
