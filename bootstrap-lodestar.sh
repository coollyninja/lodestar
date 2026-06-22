#!/usr/bin/env bash
# bootstrap-lodestar.sh — idempotent scaffolder for Lodestar in any vault.
#
# Creates the coordination bus under <OPS> (default specs/active/ops/):
#   SCRATCHPAD.md, BLOCKERS.md, signals/_TEMPLATE.md, goals/.gitkeep
# and copies the prompt templates if run from a vault that doesn't have them.
#
# Safe to re-run: never overwrites an existing file (prints "exists, skipped").
#
# Usage:
#   bash lodestar/bootstrap-lodestar.sh                 # OPS=specs/active/ops
#   OPS=ops bash lodestar/bootstrap-lodestar.sh         # custom ops dir
#
set -euo pipefail

OPS="${OPS:-specs/active/ops}"
ROOT="$(pwd)"
SIGNALS="$OPS/signals"
GOALS="$OPS/goals"

say() { printf '[bootstrap] %s\n' "$*"; }
mk()  { # mk <path> <heredoc-content via stdin>
  local f="$1"
  if [ -e "$f" ]; then say "exists, skipped: $f"; return 0; fi
  mkdir -p "$(dirname "$f")"
  cat > "$f"
  say "created: $f"
}

say "scaffolding Lodestar under $OPS/ (vault: $ROOT)"
mkdir -p "$SIGNALS" "$GOALS"

# --- SCRATCHPAD.md (the message bus) ---
mk "$OPS/SCRATCHPAD.md" <<'EOF'
# Cross-Agent Scratchpad

**Purpose:** Async threads between the orchestrator and workers. The durable
message bus. Faster than DMs; searchable forever; survives any context reset.

**How to use:**
- Add a heading `### [<from> → <to>] <subject>` at the TOP of Active threads.
- `<to>` is a worker name, `all teams`, `operator`, or `any`.
- Reply under the same heading as a nested bullet.
- Resolved? Prepend `[RESOLVED]` and a one-line resolution. Don't delete threads.

**Don't use this for:** code review (use PRs), status (use signal files),
decisions needing a paper trail (use an ADR).

---

## Active threads

<!-- newest at top -->
EOF

# --- BLOCKERS.md (the dependency ledger) ---
mk "$OPS/BLOCKERS.md" <<'EOF'
# Blockers

Cross-cutting blockers. Owner = the lane that must CLEAR it. A blocker whose
resolution is a separate signal stays Open until that signal is DONE.

## Open

| ID | Owner | Blocked work | Description | Filed |
|----|-------|--------------|-------------|-------|
| _(none)_ | | | | |

## Closed

| ID | Owner | Description | Closed |
|----|-------|-------------|--------|
EOF

# --- signals/_TEMPLATE.md ---
mk "$SIGNALS/_TEMPLATE.md" <<'EOF'
---
id: <PREFIX>-<N>
team: <worker-lane>
status: READY
owner:
blocked_by: —
unblocks:
audit_ref:
priority: <P0|P1|P2> — <one-line why>
loop_mode: continuous
cleanup_paths_provided: yes
---

# <PREFIX>-<N> — <short title>

## What
<root cause with evidence, or exact feature change>

## Why
<what breaks without it>

## Files / touch points
<exact files / repos / stacks / secrets>

## Acceptance test
<the REAL-PATH live check that closes this — not "the deploy went green">

## Notes
<gotchas, related feedback, sequencing>

## Activity log
- <date> — filed by <who> (<context>).
EOF

# --- goals/.gitkeep ---
mk "$GOALS/.gitkeep" <<'EOF'
EOF

# --- README pointer in the ops dir ---
mk "$OPS/README.md" <<'EOF'
# Ops bus

This directory is the coordination bus for Lodestar (see
`lodestar/RUNBOOK.md`).

- `signals/<PREFIX>-<N>.md` — the work queue (one unit each).
- `SCRATCHPAD.md` — async cross-agent threads (the message bus).
- `BLOCKERS.md` — cross-cutting blockers (the dependency ledger).
- `goals/` — each agent's durable /goal prompt (filled from the templates).

To spin up an agent: fill a goal template into `goals/<agent>-goal-prompt.md`,
paste it as that session's `/goal`, then start its `/loop`. See the RUNBOOK.
EOF

say "done. Next:"
say "  1) Fill lodestar/prompts/*-goal-prompt.md → $GOALS/<agent>-goal-prompt.md (per agent)"
say "  2) git add $OPS lodestar && git commit -m 'chore(stable): bootstrap coordination bus' && git push"
say "  3) Spin up the orchestrator + workers per lodestar/RUNBOOK.md"
