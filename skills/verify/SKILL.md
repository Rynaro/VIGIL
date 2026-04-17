---
name: vigil-verify
description: Phase V (Verify) — establish a reproducible failure. Deterministic-first; on two failed deterministic attempts, switch to statistical replay with confidence bands. No attribution begins without this phase passing.
when_to_use: Start of every mission. Load on mission intake, before any isolation or intervention work.
allowed-tools: run_test, run_command, read_env, capture_trace, set_seed
methodology: VIGIL
methodology_version: "1.0"
phase: V
---

# SKILL: Verify — establish reproducible failure

**Load when:** starting any mission. Unload when `reproduction.md` is schema-valid and `DETERMINISM_VERDICT ≠ intermittent`.

---

## Contract

| Field | Value |
|-------|-------|
| LLM calls permitted | Yes, for classifying failure signature and reading trace output |
| Tool budget | ≤15% of mission budget |
| Output | `reproduction.md` — schema-valid per `schemas/reproduction.v1.json` |
| Failure mode | `DETERMINISM_VERDICT = intermittent` → halt, emit `[GAP]`, escalate |

---

## The Deterministic-First Protocol

### Step 1 — Normalize the failure signature

Extract from upstream artifact (or bug report):

- **Test/command** — exact invocation that exhibits the failure
- **Error class** — categorical (`TEST_ASSERTION`, `RUNTIME_ERROR`, `BUILD_ERROR`, `TYPE_ERROR`, `LINT_VIOLATION`)
- **Key stack frames** — top 3–5 frames, normalized (strip absolute paths, line numbers preserved)
- **Observable symptom** — the specific assertion/error message

If upstream provided an APIVR-Δ `repair-failed-report.md`, copy these fields directly. Do not re-derive.

### Step 2 — First deterministic attempt

Set controlled conditions:

```
seed: <recorded_or_default>
env: <pinned per lockfile / container spec>
fs: <isolated working copy from commit SHA>
time: <frozen if test is time-sensitive>
```

Run the failing invocation. Record:
- Exit code
- stdout/stderr tail (last 200 lines)
- Comparison of observed signature to upstream signature

**Result categories:**
- `FAIL_MATCH` — fails with the same signature as upstream → proceed to Step 3
- `FAIL_DIFFERENT` — fails but with different signature → record as `[DISPUTED]`, use observed signature, proceed to Step 3
- `PASS` — did not fail → proceed to Step 3 with suspicion of flakiness

### Step 3 — Second deterministic attempt

Re-run with identical conditions. Compare to Step 2.

**Verdict matrix:**

| Step 2 | Step 3 | Verdict | Action |
|--------|--------|---------|--------|
| FAIL_MATCH | FAIL_MATCH | `stable` | Proceed to Isolate |
| FAIL_MATCH | FAIL_DIFFERENT | `flaky` | Switch to statistical |
| FAIL_MATCH | PASS | `flaky` | Switch to statistical |
| FAIL_DIFFERENT | FAIL_MATCH | `flaky` | Switch to statistical |
| FAIL_DIFFERENT | FAIL_DIFFERENT (same sig) | `stable` | Note signature drift, proceed |
| PASS | FAIL_* | `flaky` | Switch to statistical |
| PASS | PASS | `not_reproduced` | Halt — emit `[GAP]`, escalate |

---

## Statistical Mode

Triggered by `flaky` verdict. Protocol:

1. Run the failing invocation **5 times** under identical deterministic conditions.
2. Record pass/fail and observed signature for each.
3. Compute failure rate and 95% confidence interval (Wilson score interval for small N).
4. Classify:
   - **Consistent flake** — ≥3/5 fail with same signature → `DETERMINISM_VERDICT = flaky`, `[FLAKE]` marker set, proceed to Isolate. Subsequent counterfactual interventions must also use 5-run statistical evaluation.
   - **Inconsistent flake** — <3/5 fail, or signatures vary widely → `DETERMINISM_VERDICT = intermittent`, halt, escalate to FORGE or human. VIGIL cannot reliably attribute under this condition.

### Confidence band recording

For every statistical-mode decision:

```yaml
statistical_evidence:
  runs: 5
  failures: 4
  failure_rate: 0.80
  ci_95: [0.37, 0.99]
  signature_consistency: 1.0   # fraction of failures with matching signature
  verdict: flaky
```

Downstream phases inherit `statistical` mode — every intervention in Phase I will be evaluated across 5 runs, with flip requiring ≥4/5 successes.

---

## Writing `reproduction.md`

Schema-required fields:

```yaml
mission_id: VIGIL-YYYYMMDD-NNN
upstream_artifact: <pointer | null>
authority: read-only | sandbox | write
failure_signature:
  command: "<exact invocation>"
  error_class: LOGIC_ERROR | REGRESSION | BUILD_ERROR | TYPE_ERROR | LINT_VIOLATION | RUNTIME_ERROR | INTEGRATION_ERROR | ENVIRONMENT_ERROR | HEISENBUG | COMPOUND | SPEC_DEFECT
  assertion: "<observable symptom>"
  stack_top: [<frame>, <frame>, <frame>]
reproduction_mode: deterministic | statistical
reproduction_evidence:
  - attempt: 1
    result: FAIL_MATCH
    signature_match: true
    stderr_tail: <200-line excerpt ref>
  - attempt: 2
    result: FAIL_MATCH
    signature_match: true
    stderr_tail: <excerpt ref>
determinism_verdict: stable | flaky | intermittent | not_reproduced
statistical_evidence: <null | object>   # only populated in statistical mode
markers:
  - FLAKE   # only if flaky
  - GAP     # only if evidence missing
```

---

## Common pitfalls

- **Assuming the upstream signature is correct.** Re-verify. APIVR-Δ's Reflect phase may have already attempted fixes that altered the failure shape.
- **Running against the wrong commit.** Always pin to the SHA that the upstream artifact referenced.
- **Ignoring env drift.** A failure that reproduces locally but not in CI (or vice versa) is itself a finding — document the env delta.
- **Jumping to statistical mode too early.** Two deterministic attempts minimum. One inconsistent result is not enough to declare flakiness.
- **Accepting `PASS → PASS` as "fixed already."** If the upstream failure is real and your runs all pass, something about your reproduction setup is wrong. Escalate with `[GAP]`.

---

*VIGIL Phase V — the gate through which all other phases must pass*
