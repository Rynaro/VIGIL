# Canary Missions — VIGIL

> v1.13.0 DSL-format missions for `eidolons canary vigil`. A legacy
> 23-mission regression dataset exists at `evals/canary/missions.md` and is
> preserved as historical reference. The v1.13.0 validator reads only this
> file; the legacy dataset will be ported to DSL form in a follow-up wave.

---

## Mission: smoke-default

### Prompt

You are the VIGIL forensic specialist. APIVR-Δ has escalated a failure to you after 3 unsuccessful repair attempts:

> Failing test: `test_record_vote_with_valid_session`
> Error: `NoMethodError: undefined method 'bytes' for nil:NilClass`
> Stack top: `RecordVote#call:56` → `TokenGenerator#generate_uuid:14`
> Git log: commit `abc123` from 3 days ago modified `generate_uuid` to accept a session argument.
> Authority: **sandbox** (you may run interventions; you may NOT push commits).

Walk through all five phases (Verify → Isolate → Graph → Intervene → Learn) at the **outline level**. Do NOT execute tools — describe what each phase produces, the artefact path each phase emits, what hypotheses you would generate (≥3 per the plurality invariant), what intervention you would attempt, and what the final root-cause report would conclude. Conclude with a handoff section naming the primary recipient and a classification from the failure taxonomy.

### Expected output shape

A response with five phase sections. The Verify section describes a reproduction.md artefact with a deterministic / statistical verdict and a normalized failure signature. The Isolate section describes a fault-surface.md artefact with ≤8 ranked candidates and an explicit reduction trail. The Graph section describes an idg.md artefact distinguishing `[SYMPTOM]` nodes from `[ROOT-CANDIDATE]` nodes. The Intervene section names at least three `[HYPOTHESIS-N]` entries and one `[INTERVENTION-N]` with a counterfactual outcome (FLIPPED / NO_CHANGE / NEW_FAILURE) — staying inside the 5-intervention budget. The Learn section delivers a root-cause-report.md sketch with a one-sentence Summary, a classification tag from the taxonomy (LOGIC_ERROR is appropriate here), a `[ROOT-CAUSE]` block citing a finding, an Originating Decision section referencing commit `abc123`, and a handoff naming APIVR-Δ (or human if authority is insufficient).

### Validation criteria

- MUST contain heading: `## Verify`
- MUST contain heading: `## Isolate`
- MUST contain heading: `## Graph`
- MUST contain heading: `## Intervene`
- MUST contain heading: `## Learn`
- MUST contain phrase: `\[ROOT-CAUSE\]`
- MUST contain phrase: `\[HYPOTHESIS-`
- MUST contain phrase: `\[INTERVENTION-`
- MUST contain phrase: `LOGIC_ERROR|REGRESSION|RUNTIME_ERROR|INTEGRATION_ERROR|HEISENBUG|COMPOUND|SPEC_DEFECT|BUILD_ERROR|TYPE_ERROR|ENVIRONMENT_ERROR|LINT_VIOLATION`
- MUST mention paths: `reproduction.md`, `fault-surface.md`, `idg.md`
- SHOULD contain phrase: `abc123`
- SHOULD contain phrase: `APIVR`
- SHOULD contain phrase: `5.intervention`
- SHOULD have token count between 1200 and 4000

---

## Mission: root-cause-attribution

### Prompt

You are the VIGIL forensic specialist. A failing test arrives with this scenario:

> Test: `UserProfile#display_name` occasionally returns `nil`.
> Helper `truncate(name, 20)` does not handle nil. 8 call sites use the helper.
> The failing assertion is `assert_equal "Alice", truncate(user.display_name, 20)`.
> Reproduction is deterministic (specific fixture `users(:alice_without_first_name)`).
> Authority: **read-only** (no interventions may be executed — describe them only).

Run the I → G → I phase chain at the outline level: build the Information Dependency Graph, distinguish the symptom node from the root candidate, generate at least 3 hypotheses, and describe the simulated counterfactual interventions you would run. The output must clearly state that `truncate` is a `[SYMPTOM]` and `display_name` is the root candidate. The final root-cause report must NOT emit a `[ROOT-CAUSE]` marker (authority is read-only — emit `[HYPOTHESIS-N]` with confidence flag instead).

### Expected output shape

A response that opens with a Graph section enumerating nodes and edges. The Graph identifies `display_name` as the root candidate and explicitly tags `truncate` with `[SYMPTOM]`. The Intervene section lists at least three `[HYPOTHESIS-N]` entries with distinct mechanisms (per invariant I-3) and describes simulated `[INTERVENTION-N]` attempts. Because authority is read-only, the Learn section emits a `[HYPOTHESIS-N]` with confidence (H/M/L) — NOT a `[ROOT-CAUSE]` block. The handoff names APIVR-Δ (for the fix) and explicitly notes that attribution is unconfirmed without sandbox authority.

### Validation criteria

- MUST contain phrase: `\[SYMPTOM\]`
- MUST contain phrase: `display_name`
- MUST contain phrase: `\[HYPOTHESIS-`
- MUST contain phrase: `read-only`
- MUST contain phrase: `confidence`
- SHOULD contain phrase: `\[ROOT-CANDIDATE\]|root candidate`
- SHOULD contain phrase: `APIVR`
- SHOULD have token count between 800 and 2500

---

## Historical reference

The original 23-mission regression dataset (15 deterministic + 8 non-deterministic)
lives at `evals/canary/missions.md`. It predates the v1.13.0 DSL and will be ported
in a follow-up wave. The v1.13.0 validator (`eidolons canary vigil`) parses only
this file (`evals/canary-missions.md`).
