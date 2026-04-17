---
name: vigil-learn
description: Phase L (Learn) — emit verified root-cause finding with evidence chain, walk the cause back to its originating decision, persist failure signature to semantic memory for future de-duplication, route handoff to the correct downstream Eidolon.
when_to_use: After `intervention-log.md` has a SURVIVOR. Load to produce the primary deliverable.
allowed-tools: git_log, view_file, memory_write, memory_query, schema_validate
methodology: VIGIL
methodology_version: "1.0"
phase: L
---

# SKILL: Learn — emit the verified finding, preserve the lesson

**Load when:** `intervention-log.md` has a SURVIVOR with counterfactual flip. Unload after `root-cause-report.md` is schema-valid and memory entry is written.

---

## Contract

| Field | Value |
|-------|-------|
| LLM calls permitted | For composing the root-cause report and the failure-signature abstraction |
| Tool budget | ≤15% of mission budget |
| Outputs | `root-cause-report.md` (primary), `verified-patch.diff` (conditional), `failure-signature.yaml` (memory entry), handoff pointer |

---

## The Four Deliverables

### 1. `root-cause-report.md` — primary, always

Schema-validated per `schemas/root-cause-report.v1.json`. Fills `templates/root-cause-report.md`.

Core sections:

- **Summary** — one-sentence statement of the root cause
- **Findings** — `[FINDING-NNN]` records following the team-wide ATLAS schema
- **Evidence chain** — reproduction → IDG → intervention → flip
- **Root cause walk-back** — commit/decision trail that introduced the defect
- **Recommended fix** — cited by reference to `verified-patch.diff` if present
- **Handoff directive** — downstream recipient with rationale
- **Telemetry** — tokens, tool calls, interventions used, wall clock

### 2. `verified-patch.diff` — conditional

Emitted when:

- Authority ≥ `sandbox`
- Survivor intervention was a `code_change` type (not oracle injection / state correction)
- Patch scope ≤3 files and passes minimum-intervention review

Not emitted when:

- Authority = `read-only` (patches are simulated, described textually)
- Survivor was a non-code-change intervention (downstream fixer must translate)
- Root cause is `SPEC_DEFECT` (no code patch exists — SPECTRA receives this)

### 3. `failure-signature.yaml` — semantic memory entry

Added to the persistent memory ledger for future de-duplication. Purpose: if a related failure recurs, VIGIL (or any team member) can retrieve the prior attribution and its fix instead of re-investigating from scratch.

### 4. Handoff directive

A single structured pointer indicating which downstream Eidolon receives this finding and why.

---

## Root-Cause Walk-Back

The counterfactual intervention identifies *where* the defect lives. The walk-back identifies *when and why* it got there.

Procedure:

1. **Git blame the surviving intervention's target**
   ```
   git log --follow -p <path> | grep -B 5 <relevant line>
   ```
   Identify the commit(s) that introduced the defective code.

2. **Read the commit message and PR/issue** (if available)
   - What problem was it trying to solve?
   - Was there a spec? Did it change?
   - Was there a review? What was discussed?

3. **Classify the originating decision**

   | Classification | Meaning | Downstream route |
   |----------------|---------|------------------|
   | **Implementation bug** | Spec was clear; code diverged from spec | APIVR-Δ for surgical fix |
   | **Spec defect** | Spec itself was wrong or ambiguous | SPECTRA to revise spec |
   | **Contract drift** | Internal contract changed without migration | SPECTRA for planned migration; APIVR-Δ for per-caller patch |
   | **Upstream dep change** | External dependency changed behavior | APIVR-Δ to pin/adapt; IDG to document |
   | **Missing test** | Defect introduced earlier; only surfaced now | APIVR-Δ to add the missing test + fix |
   | **Environment drift** | Code correct but env/config caused failure | human or APIVR-Δ (if env-as-code) |

4. **Emit the walk-back** as a `[FINDING]` subsection:

   ```markdown
   ### Originating Decision

   [FINDING-007] The defect was introduced in commit `abc123` (2026-03-14),
   which replaced `SecureRandom.uuid` with `generate_uuid(session)` to
   scope tokens to sessions. The replacement function returns `nil` when
   `session.secret_key` is absent, a case not covered by the commit's tests.

   - evidence:
     - path: app/flows/record_vote.rb
       lines: 56
       excerpt_ref: memex://excerpt/<hash>
     - commit: abc123
       message: "Scope ballot tokens to sessions"
       pr: #472
   - classification: implementation_bug
   - downstream_route: APIVR-Δ (surgical fix)
   - confidence: H
   ```

---

## Finding Emission — Team-Wide Schema

VIGIL inherits ATLAS's `FINDING-NNN` schema. Every factual claim in the report maps to a finding record:

```yaml
FINDING-001:
  claim: "generate_uuid returns nil when session.secret_key is absent."
  evidence:
    - path: app/utils/uuid_gen.rb
      lines: 12-18
      excerpt_ref: memex://excerpt/<hash>
  confidence: H
  counterfactual_result: FLIPPED
  intervention_id: I-001
```

**Confidence rules for Learn:**

| Tier | Condition |
|------|-----------|
| `H` | Deterministic reproduction + counterfactual FLIPPED + clean IDG (single root, no disputed edges) |
| `M` | Statistical reproduction (≥0.85 CI) + FLIPPED at ≥4/5; OR deterministic FLIPPED but one disputed IDG edge |
| `L` | Not admissible for `[ROOT-CAUSE]`. Only allowed in escalation briefs as `[HYPOTHESIS-N]`. |

---

## `failure-signature.yaml` — Memory Entry

Structured for matchability against future failures. Written to the semantic memory ledger (typically `memories/vigil-failures.yaml` in the host project).

```yaml
signature_id: VSIG-YYYYMMDD-NNN
normalized_error: "ballot.token = nil at RecordVote#call"
error_class: LOGIC_ERROR
key_frames:
  - "RecordVote#call"
  - "TokenGenerator#generate_uuid"
  - "Session#secret_key"
root_cause_summary: |
  generate_uuid returns nil when session.secret_key is absent;
  callers must check for nil or supply a fallback.
root_cause_path: app/utils/uuid_gen.rb:12-18
originating_commit: abc123
category: LOGIC_ERROR
subcategory: null-guard-missing
intervention_pattern: |
  Add nil-coalescing fallback at call site OR raise in generator on
  nil input.
first_seen: 2026-04-16
frequency: 1                    # incremented on future matches
related_signatures: []          # populated if matched to prior entries
downstream_route: APIVR-Delta
mission_ref: VIGIL-20260416-001
```

### De-duplication protocol

Before writing, query existing memory for signatures matching on:

1. `error_class` exact match
2. `key_frames` overlap ≥2 frames
3. `root_cause_path` prefix match

If match found:
- Increment `frequency`
- Append current `mission_ref` to the existing entry
- Add current entry to `related_signatures` bidirectionally
- Do NOT create a new signature

If no match: write new entry.

The ledger has a recency-weighted cap (default 50 entries); older entries with `frequency = 1` are archived during consolidation.

---

## Handoff Directive

Single structured block at the end of `root-cause-report.md`:

```yaml
handoff:
  primary_recipient: APIVR-Delta | SPECTRA | IDG | FORGE | human
  rationale: "One-sentence reason for routing"
  artifact_path: "<path to root-cause-report.md>"
  supplementary_artifacts:
    - verified-patch.diff
    - intervention-log.md
  fallback_recipient: human
```

Routing rules:

| Root-cause classification | Primary | Fallback |
|---------------------------|---------|----------|
| Implementation bug, patch emitted | APIVR-Δ | human |
| Implementation bug, no patch (authority=read-only) | APIVR-Δ | human |
| Spec defect | SPECTRA | human |
| Contract drift requiring migration | SPECTRA | APIVR-Δ |
| Env/config issue | human | APIVR-Δ (if env-as-code) |
| Needs incident chronicling | IDG (in parallel) | — |
| Ambiguous after escalation | FORGE | human |

IDG is always invoked *in parallel* for high-severity failures (user-facing incidents, production regressions). VIGIL does not chronicle — IDG does — but VIGIL's report is IDG's input.

---

## Authority-Specific Output Rules

| Authority | What VIGIL emits |
|-----------|------------------|
| `read-only` | `root-cause-report.md` with simulated interventions described textually; `[ROOT-CAUSE]` downgraded to `[HYPOTHESIS-N]` with HIGH flag; no `verified-patch.diff` |
| `sandbox` | `root-cause-report.md` with executed interventions; `[ROOT-CAUSE]` with H/M confidence; `verified-patch.diff` if survivor was code-change type |
| `write` | Same as sandbox + `verified-patch.diff` ready for application to working branch |

Write authority does NOT grant VIGIL permission to auto-apply patches. Application is a downstream step performed explicitly, by APIVR-Δ or human.

---

## Pitfalls

- **Emitting `[ROOT-CAUSE]` without counterfactual flip.** Never. If the survivor was `no hypothesis flipped`, there is no `[ROOT-CAUSE]` — emit escalation.
- **Recommending improvements beyond the verified fix.** VIGIL attributes; it does not design. Broader improvements go to SPECTRA as a separate mission.
- **Skipping walk-back.** The originating commit is the most valuable information for future prevention. Don't drop it.
- **Failing to de-duplicate memory.** Signature bloat erodes the memory's value. Always query first.
- **Routing wrongly.** A spec defect sent to APIVR-Δ wastes cycles — APIVR-Δ can't fix specs. Route by classification, not by convention.

---

*VIGIL Phase L — attribute, patch if authorized, preserve the lesson*
