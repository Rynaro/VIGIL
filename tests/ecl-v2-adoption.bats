#!/usr/bin/env bats
# tests/ecl-v2-adoption.bats — Wave-3 ECL v2.0 adoption sweep
#
# Covers: the vendored v2 envelope schema shape, v1 schema retention, ISE
# (Intent, Source, Entitlement) emission on both outbound envelope templates
# (conditional root-cause-report grade vs fixed escalation-brief grade),
# canonical verify-incoming convergence with Kupo's failure-code set, the
# pending ECL 2.1 verification-attestation documentation note in
# skills/esl-hop/SKILL.md, version-stamp agreement across the 5 canonical homes,
# install.sh wiring, and drift-kill greps for stale "ECL v1.0" prose.

load helpers

# ─────────────────────────────────────────────────────────────────────────────
# v2 envelope schema — shape
# ─────────────────────────────────────────────────────────────────────────────

@test "v2: schemas/ecl/envelope.v2.json exists and is valid JSON" {
  [ -f "$VIGIL_ROOT/schemas/ecl/envelope.v2.json" ]
  if ! command -v jq &>/dev/null; then
    skip "jq not available"
  fi
  run jq empty "$VIGIL_ROOT/schemas/ecl/envelope.v2.json"
  [ "$status" -eq 0 ]
}

@test "v2: schemas/ecl/envelope.v1.json is RETAINED (not removed by the sweep)" {
  [ -f "$VIGIL_ROOT/schemas/ecl/envelope.v1.json" ]
  if ! command -v jq &>/dev/null; then
    skip "jq not available"
  fi
  run jq empty "$VIGIL_ROOT/schemas/ecl/envelope.v1.json"
  [ "$status" -eq 0 ]
}

@test "v2: envelope_version pattern is strict to 2.0" {
  if ! command -v jq &>/dev/null; then
    skip "jq not available"
  fi
  run jq -r '.properties.envelope_version.pattern' "$VIGIL_ROOT/schemas/ecl/envelope.v2.json"
  [ "$status" -eq 0 ]
  [[ "$output" == '^2\.0(\.\d+)?$' ]]
}

@test "v2: top-level ise property refs the \$defs/ise block" {
  if ! command -v jq &>/dev/null; then
    skip "jq not available"
  fi
  run jq -r '.properties.ise["$ref"]' "$VIGIL_ROOT/schemas/ecl/envelope.v2.json"
  [ "$status" -eq 0 ]
  [[ "$output" == "#/\$defs/ise" ]]
}

@test "v2: \$defs.ise requires assertion_grade" {
  if ! command -v jq &>/dev/null; then
    skip "jq not available"
  fi
  run jq -r '.["$defs"].ise.required[0]' "$VIGIL_ROOT/schemas/ecl/envelope.v2.json"
  [ "$status" -eq 0 ]
  [[ "$output" == "assertion_grade" ]]
}

@test "v2: ise.assertion_grade enum has the four ECL v2.0 §6.5.2 values" {
  if ! command -v jq &>/dev/null; then
    skip "jq not available"
  fi
  run jq -r '.["$defs"].ise.properties.assertion_grade.enum[]' "$VIGIL_ROOT/schemas/ecl/envelope.v2.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unverified"* ]]
  [[ "$output" == *"self-attested"* ]]
  [[ "$output" == *"validated"* ]]
  [[ "$output" == *"human-reviewed"* ]]
}

@test "v2: ise.receiver_authorization sub-object has the three gate fields with correct defaults" {
  if ! command -v jq &>/dev/null; then
    skip "jq not available"
  fi
  run jq -r '.["$defs"].ise.properties.receiver_authorization.properties.auto_route.default' "$VIGIL_ROOT/schemas/ecl/envelope.v2.json"
  [ "$output" == "true" ]
  run jq -r '.["$defs"].ise.properties.receiver_authorization.properties.auto_merge.default' "$VIGIL_ROOT/schemas/ecl/envelope.v2.json"
  [ "$output" == "false" ]
  run jq -r '.["$defs"].ise.properties.receiver_authorization.properties.auto_deploy.default' "$VIGIL_ROOT/schemas/ecl/envelope.v2.json"
  [ "$output" == "false" ]
}

@test "v2: performative enum matches the closed ten-value set, unchanged from v1" {
  if ! command -v jq &>/dev/null; then
    skip "jq not available"
  fi
  run jq -r '.properties.performative.enum | length' "$VIGIL_ROOT/schemas/ecl/envelope.v2.json"
  [ "$status" -eq 0 ]
  [[ "$output" == "10" ]]
  run diff \
    <(jq -c -S '.properties.performative.enum' "$VIGIL_ROOT/schemas/ecl/envelope.v1.json") \
    <(jq -c -S '.properties.performative.enum' "$VIGIL_ROOT/schemas/ecl/envelope.v2.json")
  [ "$status" -eq 0 ]
}

@test "v2: schema is self-contained (no external \$ref outside its own \$defs)" {
  if ! command -v jq &>/dev/null; then
    skip "jq not available"
  fi
  run jq -r '.. | objects | select(has("$ref")) | .["$ref"]' "$VIGIL_ROOT/schemas/ecl/envelope.v2.json"
  [ "$status" -eq 0 ]
  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    [[ "$ref" == "#/"* ]] || {
      echo "non-local \$ref found: $ref"
      return 1
    }
  done <<< "$output"
}

# ─────────────────────────────────────────────────────────────────────────────
# ISE emission — envelope templates
# ─────────────────────────────────────────────────────────────────────────────

@test "ise: root-cause-report.envelope.json declares envelope_version 2.0" {
  grep -q '"envelope_version": "2.0"' "$VIGIL_ROOT/templates/root-cause-report.envelope.json"
}

@test "ise: escalation-brief.envelope.json declares envelope_version 2.0" {
  grep -q '"envelope_version": "2.0"' "$VIGIL_ROOT/templates/escalation-brief.envelope.json"
}

@test "ise: root-cause-report.envelope.json's ise.assertion_grade is a fill-at-emit placeholder (conditional on authority)" {
  if ! command -v jq &>/dev/null; then
    skip "jq not available"
  fi
  run jq -r '.ise.assertion_grade' "$VIGIL_ROOT/templates/root-cause-report.envelope.json"
  [ "$status" -eq 0 ]
  [[ "$output" == "{{ ise.assertion_grade }}" ]]
}

@test "ise: escalation-brief.envelope.json's ise.assertion_grade is FIXED to self-attested (always)" {
  if ! command -v jq &>/dev/null; then
    skip "jq not available"
  fi
  run jq -r '.ise.assertion_grade' "$VIGIL_ROOT/templates/escalation-brief.envelope.json"
  [ "$status" -eq 0 ]
  [[ "$output" == "self-attested" ]]
}

@test "ise: the two envelope kinds' assertion_grade fields differ (root-cause-report conditional, escalation-brief fixed)" {
  if ! command -v jq &>/dev/null; then
    skip "jq not available"
  fi
  root_grade=$(jq -r '.ise.assertion_grade' "$VIGIL_ROOT/templates/root-cause-report.envelope.json")
  esc_grade=$(jq -r '.ise.assertion_grade' "$VIGIL_ROOT/templates/escalation-brief.envelope.json")
  [ "$root_grade" != "$esc_grade" ]
}

@test "ise: both envelope templates set receiver_authorization to {auto_route:true, auto_merge:false, auto_deploy:false}" {
  if ! command -v jq &>/dev/null; then
    skip "jq not available"
  fi
  for f in root-cause-report escalation-brief; do
    run jq -c '.ise.receiver_authorization' "$VIGIL_ROOT/templates/${f}.envelope.json"
    [ "$status" -eq 0 ]
    [[ "$output" == '{"auto_route":true,"auto_merge":false,"auto_deploy":false}' ]]
  done
}

@test "ise: both envelope templates' provenance.methodology_version matches vigil-1.8.0" {
  if ! command -v jq &>/dev/null; then
    skip "jq not available"
  fi
  for f in root-cause-report escalation-brief; do
    run jq -r '.ise.provenance.methodology_version' "$VIGIL_ROOT/templates/${f}.envelope.json"
    [ "$status" -eq 0 ]
    [[ "$output" == "vigil-1.8.0" ]]
  done
}

@test "ise: both envelope templates' from.version matches vigil-1.8.0's version" {
  if ! command -v jq &>/dev/null; then
    skip "jq not available"
  fi
  for f in root-cause-report escalation-brief; do
    run jq -r '.from.version' "$VIGIL_ROOT/templates/${f}.envelope.json"
    [ "$status" -eq 0 ]
    [[ "$output" == "1.8.0" ]]
  done
}

@test "ise: the validated/self-attested rule is documented in skills/intervene/SKILL.md, not just inline in emissions" {
  grep -q 'ISE Grade on the Root-Cause Report' "$VIGIL_ROOT/skills/intervene/SKILL.md"
  grep -q '\*\*.validated.\*\*.*sandbox, write' "$VIGIL_ROOT/skills/intervene/SKILL.md"
  grep -q '\*\*.self-attested.\*\*.*read-only' "$VIGIL_ROOT/skills/intervene/SKILL.md"
}

@test "ise: skills/learn/SKILL.md cross-references the intervene.md grade rule instead of restating it" {
  grep -q 'ISE Grade on the Root-Cause Report' "$VIGIL_ROOT/skills/learn/SKILL.md"
}

# ─────────────────────────────────────────────────────────────────────────────
# Pending ECL 2.1 verification-attestation note (documentation only)
# ─────────────────────────────────────────────────────────────────────────────

@test "2.1-note: skills/esl-hop/SKILL.md documents the pending ise.verification sub-block" {
  grep -q 'ise.verification' "$VIGIL_ROOT/skills/esl-hop/SKILL.md"
  grep -q 'fresh_context' "$VIGIL_ROOT/skills/esl-hop/SKILL.md"
  grep -q 'transcript_access' "$VIGIL_ROOT/skills/esl-hop/SKILL.md"
}

@test "2.1-note: skills/esl-hop/SKILL.md explicitly states the note is pending, not emitted" {
  grep -qi 'not emitted' "$VIGIL_ROOT/skills/esl-hop/SKILL.md"
  grep -q 'Draft' "$VIGIL_ROOT/skills/esl-hop/SKILL.md"
}

@test "2.1-note: ECL_VERSION file is unaffected by the 2.1 note (stays 2.0)" {
  run cat "$VIGIL_ROOT/ECL_VERSION"
  [[ "$output" == "2.0" ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Canonical verify-incoming convergence with ../Kupo
# ─────────────────────────────────────────────────────────────────────────────

@test "convergence: verify-incoming.md failure codes include CONTEXT_OVER_BUDGET (matches Kupo)" {
  grep -q 'CONTEXT_OVER_BUDGET' "$VIGIL_ROOT/skills/verify-incoming/SKILL.md"
}

@test "convergence: verify-incoming.md failure codes include MISSING_REQUIRED_SECTION (matches Kupo)" {
  grep -q 'MISSING_REQUIRED_SECTION' "$VIGIL_ROOT/skills/verify-incoming/SKILL.md"
}

@test "convergence: verify-incoming.md drops the stale 'six Eidolons' count" {
  run grep -c 'six Eidolons' "$VIGIL_ROOT/skills/verify-incoming/SKILL.md"
  [[ "$output" == "0" ]]
  grep -q 'All Eidolons in the roster ship this gate' "$VIGIL_ROOT/skills/verify-incoming/SKILL.md"
}

@test "convergence: verify-incoming.md accepted-artifact table is preserved (VIGIL-specific inbound edges)" {
  grep -q '| `apivr` | PROPOSE, INFORM | `change-summary` |' "$VIGIL_ROOT/skills/verify-incoming/SKILL.md"
  grep -q '| `atlas` | PROPOSE, INFORM | `scout-report` |' "$VIGIL_ROOT/skills/verify-incoming/SKILL.md"
  grep -q '| `spectra` | PROPOSE, INFORM | `spec` |' "$VIGIL_ROOT/skills/verify-incoming/SKILL.md"
  grep -q '| `idg` | PROPOSE, INFORM | `doc-report` |' "$VIGIL_ROOT/skills/verify-incoming/SKILL.md"
  grep -q '| `forge` | PROPOSE, INFORM, CRITIQUE | `reasoning-report` |' "$VIGIL_ROOT/skills/verify-incoming/SKILL.md"
}

@test "convergence: verify-incoming.md posture is still BLOCKING (unchanged by convergence)" {
  grep -qE 'REFUSE|SHALL NOT|blocking' "$VIGIL_ROOT/skills/verify-incoming/SKILL.md"
  # Same exact-case patterns as tests/verify-incoming.bats' S2 — deliberately
  # NOT case-insensitive, since the lowercase prose phrase "warn-only" is used
  # legitimately as a historical contrast ("Blocking, not warn-only").
  run grep -cE 'payload is always processed|WARN.ONLY|warn_only' "$VIGIL_ROOT/skills/verify-incoming/SKILL.md"
  [[ "$output" == "0" ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Drift-kill: the 3 stale "ECL v1.0" prose references, and no strays left
# ─────────────────────────────────────────────────────────────────────────────


@test "drift: SPEC.md §11 ECL Compatibility targets v2.0" {
  grep -q 'emits ECL v2.0 envelopes by default' "$VIGIL_ROOT/SPEC.md"
  run grep -c 'ECL v1\.0' "$VIGIL_ROOT/SPEC.md"
  [[ "$output" == "0" ]]
}

@test "drift: skills/learn/SKILL.md Envelope Emission section targets v2.0" {
  grep -q 'emit the ECL v2.0 envelope sidecar' "$VIGIL_ROOT/skills/learn/SKILL.md"
  run grep -c 'ECL v1\.0' "$VIGIL_ROOT/skills/learn/SKILL.md"
  [[ "$output" == "0" ]]
}

@test "drift: no tracked methodology source (outside CHANGELOG.md) declares stale 'ECL v1.0' emission prose" {
  cd "$VIGIL_ROOT"
  run grep -rl 'ECL v1\.0' \
    PERSONA.md AGENTS.md SPEC.md README.md install.sh \
    hosts/*.md evals/canary-missions.md \
    skills/*.md templates/*.md examples/*.json 2>/dev/null
  # DESIGN-RATIONALE.md's D4 fan-out rationale ("no multicast performative in
  # ECL v1.0") is a historical-decision statement, still true as stated, and
  # is intentionally excluded from this scan (it does not assert VIGIL's
  # *current* target version, unlike the 3 fixed emission-prose spots above).
  if [ "$status" -eq 0 ]; then
    echo "Stale 'ECL v1.0' emission prose found in: $output" >&3
    false
  fi
}

@test "drift: ECL_VERSION file declares 2.0" {
  run cat "$VIGIL_ROOT/ECL_VERSION"
  [[ "$output" == "2.0" ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Version-stamp agreement — the 5 canonical homes, bumped to 1.8.0
# ─────────────────────────────────────────────────────────────────────────────








# ─────────────────────────────────────────────────────────────────────────────
# install.sh — end-to-end wiring still holds after the sweep
# ─────────────────────────────────────────────────────────────────────────────
