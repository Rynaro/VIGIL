#!/usr/bin/env bash
# VIGIL installer — EIIS-1.0 conformant
# Usage: bash install.sh [OPTIONS]
set -euo pipefail

EIDOLON_NAME="vigil"
EIDOLON_VERSION="1.0.1"
METHODOLOGY="VIGIL"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --------------------------------------------------------------------------- #
# Defaults
# --------------------------------------------------------------------------- #
TARGET="./.eidolons/${EIDOLON_NAME}"
HOSTS="auto"
MODE="read-only"
FORCE=false
DRY_RUN=false
NON_INTERACTIVE=false
MANIFEST_ONLY=false
SHARED_DISPATCH=false

# --------------------------------------------------------------------------- #
# Help
# --------------------------------------------------------------------------- #
usage() {
  cat <<EOF
Usage: bash install.sh [OPTIONS]

Install the VIGIL v${EIDOLON_VERSION} forensic debugger methodology into
the current consumer project.

Options:
  --target DIR            Target install dir (default: ${TARGET})
  --hosts LIST            claude-code,copilot,cursor,opencode,all (default: auto)
  --mode MODE             Authority mode: read-only|sandbox|write (default: ${MODE})
  --shared-dispatch       Compose marker-bounded section in root AGENTS.md /
                          CLAUDE.md / .github/copilot-instructions.md (opt-in).
  --no-shared-dispatch    Skip root dispatch files (default).
  --force                 Overwrite existing install without prompting
  --dry-run               Print actions without writing any files
  --non-interactive       No prompts; fail on ambiguity (meta-installer mode)
  --manifest-only         Only emit install.manifest.json (no file copies)
  --version               Print Eidolon version and exit
  -h, --help              Show this help and exit

Host detection (--hosts auto):
  claude-code   detected if CLAUDE.md or .claude/ exists
  copilot       detected if .github/ exists
  cursor        detected if .cursor/ or .cursorrules exists
  opencode      detected if .opencode/ exists

Authority modes (--mode):
  read-only     Interventions simulated only; no sandbox execution (safest default)
  sandbox       Interventions run in isolated adapter; working tree untouched
  write         Sandbox first; may emit verified-patch.diff (never auto-applies)

Examples:
  bash install.sh
  bash install.sh --target ./vendor/vigil --hosts claude-code,copilot
  bash install.sh --mode sandbox --non-interactive --force
  bash install.sh --dry-run
EOF
}

# --------------------------------------------------------------------------- #
# Argument parsing
# --------------------------------------------------------------------------- #
# Legacy positional target and --mode=VALUE are preserved as a compatibility
# shim for pre-v1.0.1 callers. Prefer --target DIR and --mode MODE.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)               TARGET="$2"; shift 2 ;;
    --hosts)                HOSTS="$2"; shift 2 ;;
    --mode)                 MODE="$2"; shift 2 ;;
    --mode=*)               MODE="${1#--mode=}"; shift ;;
    --shared-dispatch)      SHARED_DISPATCH=true; shift ;;
    --no-shared-dispatch)   SHARED_DISPATCH=false; shift ;;
    --force)                FORCE=true; shift ;;
    --dry-run)              DRY_RUN=true; shift ;;
    --non-interactive)      NON_INTERACTIVE=true; shift ;;
    --manifest-only)        MANIFEST_ONLY=true; shift ;;
    --version)              echo "${EIDOLON_VERSION}"; exit 0 ;;
    -h|--help)              usage; exit 0 ;;
    -*)                     echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)
      TARGET="$1"
      echo "Warning: positional target is deprecated; use --target DIR instead" >&2
      shift ;;
  esac
done

# --------------------------------------------------------------------------- #
# Validate mode
# --------------------------------------------------------------------------- #
case "$MODE" in
  read-only|sandbox|write) ;;
  *)
    echo "ERROR: Invalid --mode '$MODE'. Must be one of: read-only, sandbox, write" >&2
    exit 2
    ;;
esac

# --------------------------------------------------------------------------- #
# Utilities
# --------------------------------------------------------------------------- #
log()  { echo "[vigil] $*"; }
warn() { echo "[vigil] WARN: $*" >&2; }

do_action() {
  local desc="$1"; shift
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [dry-run] ${desc}"
  else
    "$@"
  fi
}

sha256_file() {
  local f="$1"
  if command -v shasum &>/dev/null; then
    shasum -a 256 "$f" | awk '{print $1}'
  elif command -v sha256sum &>/dev/null; then
    sha256sum "$f" | awk '{print $1}'
  elif command -v openssl &>/dev/null; then
    openssl dgst -sha256 "$f" | awk '{print $NF}'
  else
    echo "0000000000000000000000000000000000000000000000000000000000000000"
  fi
}

# --------------------------------------------------------------------------- #
# Source sanity check
# --------------------------------------------------------------------------- #
if [[ ! -f "${SCRIPT_DIR}/VIGIL.md" ]]; then
  echo "ERROR: install.sh must run from the VIGIL source directory (VIGIL.md not found)" >&2
  exit 3
fi

# --------------------------------------------------------------------------- #
# Host detection
# --------------------------------------------------------------------------- #
detect_hosts() {
  local detected=()
  [[ -f "CLAUDE.md" || -d ".claude" ]]       && detected+=("claude-code")
  [[ -d ".github" ]]                          && detected+=("copilot")
  [[ -d ".cursor" || -f ".cursorrules" ]]     && detected+=("cursor")
  [[ -d ".opencode" ]]                        && detected+=("opencode")
  printf "%s\n" "${detected[@]:-}"
}

if [[ "$HOSTS" == "auto" ]]; then
  HOSTS_ARRAY=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && HOSTS_ARRAY+=("$line")
  done < <(detect_hosts)
  if [[ ${#HOSTS_ARRAY[@]} -eq 0 ]]; then
    warn "No host config directories detected. Using raw install only."
    HOSTS_ARRAY=("raw")
  fi
elif [[ "$HOSTS" == "all" ]]; then
  HOSTS_ARRAY=("claude-code" "copilot" "cursor" "opencode")
else
  IFS=',' read -ra HOSTS_ARRAY <<< "$HOSTS"
fi

hosts_include() { local h; for h in "${HOSTS_ARRAY[@]}"; do [[ "$h" == "$1" ]] && return 0; done; return 1; }

# --------------------------------------------------------------------------- #
# Idempotency check
# --------------------------------------------------------------------------- #
EXISTING_MANIFEST="${TARGET}/install.manifest.json"
if [[ -f "$EXISTING_MANIFEST" && "$FORCE" != "true" ]]; then
  EXISTING_VER=$(grep -o '"version":"[^"]*"' "$EXISTING_MANIFEST" 2>/dev/null | head -1 | cut -d'"' -f4 || echo "unknown")
  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    echo "Already installed v${EXISTING_VER} at ${TARGET}. Pass --force to overwrite." >&2
    exit 3
  fi
  read -rp "[vigil] Already installed v${EXISTING_VER} at ${TARGET}. Overwrite? [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

# --------------------------------------------------------------------------- #
# Announce
# --------------------------------------------------------------------------- #
log "Installing VIGIL v${EIDOLON_VERSION} → ${TARGET}"
log "Mode: ${MODE}"
log "Hosts: ${HOSTS_ARRAY[*]}"
[[ "$DRY_RUN" == "true" ]]       && log "Dry-run (no files written)"
[[ "$MANIFEST_ONLY" == "true" ]] && log "Manifest-only"

# --------------------------------------------------------------------------- #
# Directory creation
# --------------------------------------------------------------------------- #
FILES_WRITTEN=()

maybe_mkdir() {
  do_action "mkdir -p $1" mkdir -p "$1"
}

if [[ "$MANIFEST_ONLY" != "true" ]]; then
  maybe_mkdir "${TARGET}"
  maybe_mkdir "${TARGET}/skills/verify"
  maybe_mkdir "${TARGET}/skills/isolate"
  maybe_mkdir "${TARGET}/skills/graph"
  maybe_mkdir "${TARGET}/skills/intervene"
  maybe_mkdir "${TARGET}/skills/learn"
  maybe_mkdir "${TARGET}/templates"
  maybe_mkdir "${TARGET}/schemas"
  maybe_mkdir "${TARGET}/hosts"
  maybe_mkdir "${TARGET}/evals/canary"
fi

# --------------------------------------------------------------------------- #
# Copy methodology files
# --------------------------------------------------------------------------- #
copy_file() {
  local src="$1" dst="$2" role="$3"
  do_action "copy ${src} → ${dst}" cp "${SCRIPT_DIR}/${src}" "${dst}"
  if [[ "$DRY_RUN" != "true" ]]; then
    local chk; chk=$(sha256_file "${dst}")
    FILES_WRITTEN+=("{\"path\":\"${dst}\",\"sha256\":\"${chk}\",\"role\":\"${role}\",\"mode\":\"created\"}")
  fi
}

if [[ "$MANIFEST_ONLY" != "true" ]]; then
  copy_file "agent.md"            "${TARGET}/agent.md"            "entry-point"
  copy_file "VIGIL.md"            "${TARGET}/VIGIL.md"            "spec"
  copy_file "AGENTS.md"           "${TARGET}/AGENTS.md"           "entry-point"
  copy_file "CLAUDE.md"           "${TARGET}/CLAUDE.md"           "dispatch"
  copy_file "DESIGN-RATIONALE.md" "${TARGET}/DESIGN-RATIONALE.md" "other"
  copy_file "README.md"           "${TARGET}/README.md"           "other"
  copy_file "CHANGELOG.md"        "${TARGET}/CHANGELOG.md"        "other"

  for phase in verify isolate graph intervene learn; do
    copy_file "skills/${phase}/SKILL.md" "${TARGET}/skills/${phase}/SKILL.md" "skill"
  done

  for tpl in root-cause-report verified-patch failure-signature escalation-brief; do
    copy_file "templates/${tpl}.md" "${TARGET}/templates/${tpl}.md" "template"
  done

  for schema in reproduction intervention-log root-cause-report; do
    copy_file "schemas/${schema}.v1.json" "${TARGET}/schemas/${schema}.v1.json" "other"
  done

  for host in claude-code cursor copilot opencode; do
    [[ -f "${SCRIPT_DIR}/hosts/${host}.md" ]] && \
      copy_file "hosts/${host}.md" "${TARGET}/hosts/${host}.md" "dispatch"
  done

  if [[ -d "${SCRIPT_DIR}/evals/canary" ]]; then
    for f in "${SCRIPT_DIR}"/evals/canary/*.md; do
      [[ -e "$f" ]] || continue
      copy_file "evals/canary/$(basename "$f")" "${TARGET}/evals/canary/$(basename "$f")" "other"
    done
  fi
fi

# --------------------------------------------------------------------------- #
# Shared dispatch block (opt-in marker-bounded section in root files)
# --------------------------------------------------------------------------- #
SHARED_BLOCK="## VIGIL — Forensic debugger (v${EIDOLON_VERSION})

Entry:     \`${TARGET}/agent.md\`
Full spec: \`${TARGET}/VIGIL.md\`
Cycle:     V (Verify) → I (Isolate) → G (Graph) → I (Intervene) → L (Learn)
Authority: ${MODE}

**P0 (non-negotiable):** reproduction gates attribution (≥2 deterministic runs or statistical CI ≥85%); dependency-graph ranking (never temporal order); ≥3 hypotheses before intervention; counterfactual-gated blame (minimal flip from fail→success); ≤5 intervention budget then escalate; flag-gated authority (read-only | sandbox | write — write never inferred); evidence-anchored findings with \`path:line\` + confidence tier; non-determinism declared, not masked."

upsert_eidolon_block() {
  local dst="$1" content="$2" role="$3"
  local start="<!-- eidolon:${EIDOLON_NAME} start -->"
  local end="<!-- eidolon:${EIDOLON_NAME} end -->"

  if [[ "$DRY_RUN" == "true" ]]; then
    local action="append"
    [[ -f "$dst" ]] && grep -qF "$start" "$dst" 2>/dev/null && action="rewrite"
    echo "  [dry-run] ${action} eidolon:${EIDOLON_NAME} block in ${dst}"
    return
  fi

  mkdir -p "$(dirname "$dst")" 2>/dev/null || true
  [[ -L "$dst" ]] && rm -f "$dst"

  local content_file mode tmp
  content_file="$(mktemp)"
  printf '%s\n' "$content" > "$content_file"

  if [[ -f "$dst" ]] && grep -qF "$start" "$dst" 2>/dev/null; then
    mode="rewritten"
    tmp="$(mktemp)"
    awk -v start="$start" -v end="$end" -v cf="$content_file" '
      BEGIN { in_block = 0 }
      $0 == start {
        print start
        while ((getline line < cf) > 0) print line
        close(cf)
        in_block = 1
        next
      }
      $0 == end {
        print end
        in_block = 0
        next
      }
      !in_block { print }
    ' "$dst" > "$tmp"
    mv "$tmp" "$dst"
  elif [[ -f "$dst" ]]; then
    mode="appended"
    {
      printf '\n%s\n' "$start"
      cat "$content_file"
      printf '%s\n' "$end"
    } >> "$dst"
  else
    mode="created"
    {
      printf '%s\n' "$start"
      cat "$content_file"
      printf '%s\n' "$end"
    } > "$dst"
  fi

  rm -f "$content_file"
  local chk; chk=$(sha256_file "$dst")
  FILES_WRITTEN+=("{\"path\":\"${dst}\",\"sha256\":\"${chk}\",\"role\":\"${role}\",\"mode\":\"${mode}\"}")
}

if [[ "$MANIFEST_ONLY" != "true" && "$SHARED_DISPATCH" == "true" ]]; then
  upsert_eidolon_block "AGENTS.md" "$SHARED_BLOCK" "dispatch"
fi

# --------------------------------------------------------------------------- #
# Host wiring
# --------------------------------------------------------------------------- #

# ---- claude-code ---------------------------------------------------------- #
if hosts_include "claude-code" && [[ "$MANIFEST_ONLY" != "true" ]]; then
  log "Wiring: claude-code"

  [[ "$SHARED_DISPATCH" == "true" ]] && upsert_eidolon_block "CLAUDE.md" "$SHARED_BLOCK" "dispatch"

  do_action "mkdir -p .claude/agents" mkdir -p ".claude/agents"

  AGENT_CONTENT="---
name: vigil
description: Forensic debugger for code failures resistant to normal repair. Use when a test fails in a non-obvious way, when APIVR-Δ has exhausted its Reflect loop, for heisenbugs, compound failures, or regressions of unclear origin. Runs the five-phase VIGIL pipeline (Verify → Isolate → Graph → Intervene → Learn), emits evidence-anchored root-cause attribution.
when_to_use: After APIVR-Δ escalation; post-hoc failure analysis; heisenbugs and flaky tests; compound failures spanning multiple modules; any \"why did this fail\" question where log-only speculation would be inadmissible.
tools: Read, Grep, Glob, Bash(git log:*), Bash(git bisect:*), Bash(git show:*), Bash(rg:*)
methodology: VIGIL
methodology_version: \"1.0\"
role: Forensic debugger — root-cause attribution
handoffs: [apivr, spectra, idg, forge]
authority: ${MODE}
---

# VIGIL — Forensic Debugger Agent

You execute the VIGIL methodology: **V**erify → **I**solate → **G**raph →
**I**ntervene → **L**earn. You attribute root causes under evidence
discipline. You do NOT plan, implement, or chronicle — you decide what
went wrong. Full spec: \`${TARGET}/VIGIL.md\`.

Authority: **${MODE}**. See \`${TARGET}/agent.md\` for P0 invariants
and phase-skill triggers."

  if [[ "$DRY_RUN" != "true" ]]; then
    printf "%s\n" "$AGENT_CONTENT" > ".claude/agents/vigil.md"
    chk=$(sha256_file ".claude/agents/vigil.md")
    FILES_WRITTEN+=("{\"path\":\".claude/agents/vigil.md\",\"sha256\":\"${chk}\",\"role\":\"dispatch\",\"mode\":\"created\"}")
  else
    echo "  [dry-run] created .claude/agents/vigil.md"
  fi
fi

# ---- copilot -------------------------------------------------------------- #
if hosts_include "copilot" && [[ "$MANIFEST_ONLY" != "true" ]]; then
  log "Wiring: copilot"
  [[ "$SHARED_DISPATCH" == "true" ]] && \
    upsert_eidolon_block ".github/copilot-instructions.md" "$SHARED_BLOCK" "dispatch"
fi

# ---- cursor --------------------------------------------------------------- #
if hosts_include "cursor" && [[ "$MANIFEST_ONLY" != "true" ]]; then
  log "Wiring: cursor"
  do_action "mkdir -p .cursor/rules" mkdir -p ".cursor/rules"
  CURSOR_RULE=".cursor/rules/vigil.mdc"
  if [[ ! -f "$CURSOR_RULE" || "$FORCE" == "true" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "  [dry-run] write ${CURSOR_RULE}"
    else
      cat > "$CURSOR_RULE" <<EOF
---
description: "VIGIL — forensic debugger for code failures resistant to normal repair. Runs V→I→G→I→L."
globs: "**/*"
alwaysApply: false
---

See ${TARGET}/agent.md for the always-loaded entry and ${TARGET}/VIGIL.md
for the authoritative specification. Authority: ${MODE}.
EOF
      chk=$(sha256_file "$CURSOR_RULE")
      FILES_WRITTEN+=("{\"path\":\"${CURSOR_RULE}\",\"sha256\":\"${chk}\",\"role\":\"dispatch\",\"mode\":\"created\"}")
    fi
  else
    log "  skip ${CURSOR_RULE} (exists — pass --force to overwrite)"
  fi
fi

# ---- opencode ------------------------------------------------------------- #
if hosts_include "opencode" && [[ "$MANIFEST_ONLY" != "true" ]]; then
  log "Wiring: opencode"
  do_action "mkdir -p .opencode/agents" mkdir -p ".opencode/agents"
  OC_AGENT=".opencode/agents/vigil.md"
  if [[ ! -f "$OC_AGENT" || "$FORCE" == "true" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "  [dry-run] write ${OC_AGENT}"
    else
      cat > "$OC_AGENT" <<EOF
---
mode: primary
description: "VIGIL v${EIDOLON_VERSION} — forensic debugger, V→I→G→I→L, authority ${MODE}"
---

You are the VIGIL forensic debugger. Full rules: \`${TARGET}/AGENTS.md\`.
Always-loaded profile: \`${TARGET}/agent.md\`. Full spec: \`${TARGET}/VIGIL.md\`.
Phase skills: \`${TARGET}/skills/<phase>/SKILL.md\` — load per phase.
Authority: ${MODE}.
EOF
      chk=$(sha256_file "$OC_AGENT")
      FILES_WRITTEN+=("{\"path\":\"${OC_AGENT}\",\"sha256\":\"${chk}\",\"role\":\"dispatch\",\"mode\":\"created\"}")
    fi
  else
    log "  skip ${OC_AGENT} (exists — pass --force to overwrite)"
  fi
fi

# --------------------------------------------------------------------------- #
# Per-project config and memory ledger (VIGIL-specific)
# --------------------------------------------------------------------------- #
CONFIG_DIR="$(dirname "$TARGET")/.vigil"
if [[ "$MANIFEST_ONLY" != "true" && ! -d "$CONFIG_DIR" ]]; then
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [dry-run] generate ${CONFIG_DIR}/config.yml"
  else
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/config.yml" <<EOF
# VIGIL per-project configuration
# Generated by installer on $(date -u +%Y-%m-%dT%H:%M:%SZ)

authority:
  default_mode: $MODE
  allow_write: $([ "$MODE" = "write" ] && echo "true" || echo "false")

sandbox:
  # Choose adapter based on your project stack:
  #   docker | podman | language_native | firejail | bubblewrap
  adapter: language_native
  timeout_s: 300
  resource_limits:
    memory_mb: 2048
    cpus: 2

memory:
  path: memories/vigil-failures.yaml
  signature_cap: 50
  consolidation_strategy: recency_weighted

trace_source:
  type: none                             # none | otel | otlp_file | structured_log
EOF
    log "  generated: ${CONFIG_DIR}/config.yml"
  fi
fi

MEM_DIR="$(dirname "$TARGET")/memories"
if [[ "$MANIFEST_ONLY" != "true" && ! -e "$MEM_DIR/vigil-failures.yaml" ]]; then
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [dry-run] generate ${MEM_DIR}/vigil-failures.yaml"
  else
    mkdir -p "$MEM_DIR"
    cat > "$MEM_DIR/vigil-failures.yaml" <<EOF
# VIGIL failure signature ledger
# Managed automatically by VIGIL Phase L
# Soft cap: 50 entries — older single-occurrence entries archive to vigil-failures.archive.yaml

version: "1.0"
methodology: VIGIL
signatures: []
EOF
    log "  generated: ${MEM_DIR}/vigil-failures.yaml"
  fi
fi

# --------------------------------------------------------------------------- #
# Token measurement
# --------------------------------------------------------------------------- #
AGENT_MD_PATH="${TARGET}/agent.md"
if [[ "$DRY_RUN" != "true" && -f "$AGENT_MD_PATH" ]]; then
  WORD_COUNT=$(wc -w < "$AGENT_MD_PATH")
else
  WORD_COUNT=$(wc -w < "${SCRIPT_DIR}/agent.md")
fi
AGENT_TOKENS=$(awk "BEGIN {printf \"%d\", ${WORD_COUNT}/0.75}")

if [[ "$AGENT_TOKENS" -gt 1000 ]]; then
  warn "agent.md exceeds 1000-token budget (estimated ${AGENT_TOKENS} tokens)."
  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    echo "Error: agent.md token budget exceeded in --non-interactive mode." >&2
    exit 4
  fi
fi

# --------------------------------------------------------------------------- #
# Write install.manifest.json
# --------------------------------------------------------------------------- #
INSTALLED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
HOSTS_JSON="$(printf '"%s",' "${HOSTS_ARRAY[@]}" | sed 's/,$//')"

FILES_JSON=""
if [[ ${#FILES_WRITTEN[@]} -gt 0 ]]; then
  FILES_JSON="$(printf '%s,' "${FILES_WRITTEN[@]}" | sed 's/,$//')"
fi

MANIFEST_PATH="${TARGET}/install.manifest.json"
if [[ "$DRY_RUN" != "true" ]]; then
  mkdir -p "${TARGET}"
  cat > "${MANIFEST_PATH}" <<MANIFEST_EOF
{
  "eidolon": "${EIDOLON_NAME}",
  "version": "${EIDOLON_VERSION}",
  "methodology": "${METHODOLOGY}",
  "installed_at": "${INSTALLED_AT}",
  "target": "${TARGET}",
  "hosts_wired": [${HOSTS_JSON}],
  "files_written": [${FILES_JSON}],
  "handoffs_declared": {
    "upstream": [],
    "downstream": ["apivr", "spectra", "idg", "forge"]
  },
  "token_budget": {
    "entry": ${AGENT_TOKENS},
    "working_set_target": 3500
  },
  "security": {
    "reads_repo": true,
    "reads_network": false,
    "writes_repo": $([ "$MODE" = "write" ] && echo "true" || echo "false"),
    "persists": [".vigil/config.yml", "memories/vigil-failures.yaml"]
  },
  "authority_mode": "${MODE}"
}
MANIFEST_EOF
  log "Manifest: ${MANIFEST_PATH}"
fi

# --------------------------------------------------------------------------- #
# Success banner
# --------------------------------------------------------------------------- #
echo ""
echo "✓ VIGIL v${EIDOLON_VERSION} installed → ${TARGET}"
echo "✓ agent.md: ${AGENT_TOKENS} tokens (budget: ≤1000)"
echo "✓ Hosts wired: ${HOSTS_ARRAY[*]}"
echo "✓ Authority mode: ${MODE}"
echo ""
echo "Smoke test — paste this into your AI host:"
echo "─────────────────────────────────────────────────────────────────────────"
echo "VIGIL, a flaky test fails ~30% of runs with TypeError: Cannot read"
echo "property 'id' of undefined. Other tests in the same file pass. Please"
echo "attribute root cause via the V→I→G→I→L cycle."
echo "─────────────────────────────────────────────────────────────────────────"
echo ""
echo "Expected: VIGIL emits reproduction.md (statistical mode after 2 divergent"
echo "deterministic attempts), fault-surface.md, an IDG distinguishing symptom"
echo "from candidates, counterfactual interventions (≤5), and a root-cause-report.md"
echo "with confidence tier and reversal conditions."
echo ""
echo "Per-project config: ${CONFIG_DIR}/config.yml"
echo "Memory ledger:      ${MEM_DIR}/vigil-failures.yaml"
