#!/usr/bin/env bash
# install.sh — pull Lodestar into a vault and wire it into the wiki.
#
# Run from the ROOT of the target vault:
#   curl -fsSL https://raw.githubusercontent.com/coollyninja/lodestar/main/install.sh | bash
#   # or, if you've cloned this repo somewhere:
#   bash /path/to/lodestar/install.sh
#
# What it does (all idempotent):
#   1. Vendors the kit into projects/lodestar/ (clone; projects/ is usually gitignored).
#   2. Runs bootstrap-lodestar.sh to scaffold the ops bus (signals/SCRATCHPAD/BLOCKERS/goals).
#   3. Creates a wiki entity page wiki/entities/lodestar.md describing the framework.
#   4. Prints next steps.
#
# Env overrides:
#   LODESTAR_REPO   (default https://github.com/coollyninja/lodestar.git)
#   OPS             (default specs/active/ops)   — the ops bus dir
#   WIKI            (default wiki)               — the wiki dir
#
set -euo pipefail

LODESTAR_REPO="${LODESTAR_REPO:-https://github.com/coollyninja/lodestar.git}"
OPS="${OPS:-specs/active/ops}"
WIKI="${WIKI:-wiki}"
VAULT="$(pwd)"
DEST="projects/lodestar"

say() { printf '[lodestar-install] %s\n' "$*"; }

# Sanity: are we in a vault root? (has a .git or a CLAUDE.md is a good heuristic)
if [ ! -e .git ] && [ ! -e CLAUDE.md ]; then
  say "WARNING: this doesn't look like a vault root (no .git / CLAUDE.md). Continuing anyway."
fi

# 1. Vendor the kit ---------------------------------------------------------
if [ -d "$DEST/.git" ]; then
  say "updating existing $DEST ..."
  git -C "$DEST" pull --ff-only || say "(pull skipped — local changes?)"
else
  say "cloning Lodestar into $DEST ..."
  mkdir -p projects
  git clone --depth 1 "$LODESTAR_REPO" "$DEST"
fi

# 2. Scaffold the ops bus ---------------------------------------------------
say "scaffolding the ops bus under $OPS/ ..."
OPS="$OPS" bash "$DEST/bootstrap-lodestar.sh"

# 3. Wire the wiki ----------------------------------------------------------
WIKI_PAGE="$WIKI/entities/lodestar.md"
mkdir -p "$WIKI/entities"
if [ -e "$WIKI_PAGE" ]; then
  say "wiki page exists, skipped: $WIKI_PAGE"
else
  TODAY="$(date +%Y-%m-%d 2>/dev/null || echo unknown)"
  cat > "$WIKI_PAGE" <<EOF
---
title: Lodestar
tags: [framework, orchestration, multi-agent, ops]
sources: [projects/lodestar/]
created: $TODAY
updated: $TODAY
tldr: Reset-proof orchestrator+worker framework. The vault git repo is the shared memory and message bus; stateless agents reconstitute context from committed files every wake.
---

# Lodestar

> [!fact] Lodestar is a vault-agnostic framework for running an **orchestrator**
> agent that coordinates **worker** agents through committed git files. Source:
> [[projects/lodestar]] (vendored from \`coollyninja/lodestar\`).

## What it is
The git vault is the **shared memory and message bus**. Agents are stateless
processes that reconstitute their full context from disk on every wake — kill any
agent, respawn from its goal file, and it continues. Context resets are non-events.

## The bus (this vault)
- \`$OPS/signals/\` — the work queue (one \`<PREFIX>-<N>.md\` per unit).
- \`$OPS/SCRATCHPAD.md\` — async cross-agent threads (the message bus).
- \`$OPS/BLOCKERS.md\` — cross-cutting blockers (the dependency ledger).
- \`$OPS/goals/\` — each agent's durable \`/goal\` prompt (its identity).

## How to use it
See [[projects/lodestar]] \`RUNBOOK.md\` for spinning up orchestrators + workers,
and \`GIT-SYNC.md\` for the cross-machine pull/commit/push discipline.

## Updating
Re-run \`bash projects/lodestar/install.sh\` (idempotent) or
\`git -C projects/lodestar pull\` to pull a newer version of the kit.
EOF
  say "created wiki page: $WIKI_PAGE"
fi

# 4. Next steps -------------------------------------------------------------
say "done."
say "next:"
say "  1) Fill projects/lodestar/prompts/*-goal-prompt.md → $OPS/goals/<agent>-goal-prompt.md (per agent/lane)."
say "  2) Link the wiki page from your wiki index.md if you keep one."
say "  3) Commit the vault changes: git add $OPS $WIKI/entities/lodestar.md && git commit -m 'chore(lodestar): install framework' && git push"
say "  4) Spin up the orchestrator + workers per projects/lodestar/RUNBOOK.md."
say ""
say "(projects/ is typically gitignored, so projects/lodestar/ itself won't be committed —"
say " it's a vendored tool. The committed artifacts are the ops bus + the wiki page.)"
