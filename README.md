# Lodestar

A reset-proof, vault-agnostic framework for running an **orchestrator** agent
that coordinates **worker** agents through committed git files. The vault repo
is the shared memory and message bus; agents are stateless processes that
reconstitute their full context from disk on every wake. Kill any agent, respawn
it from its goal file, and it continues — context resets are non-events.

## Start here
- **`RUNBOOK.md`** — the full process: spinning up orchestrators + workers, the
  per-wake loop, the signal lifecycle, failure & recovery.
- **`GIT-SYNC.md`** — the pull/commit/push discipline that keeps the vault in
  sync across separate machines/containers (the load-bearing part).

## The kit
```
lodestar/
├── README.md                 # this file
├── RUNBOOK.md                # the process
├── GIT-SYNC.md               # git-sync protocol (cross-machine sync)
├── bootstrap-lodestar.sh       # idempotent scaffolder for a new vault
└── prompts/
    ├── orchestrator-goal-prompt.md   # orchestrator /goal template
    ├── worker-goal-prompt.md         # worker /goal template
    ├── loop-prompt.md                # /loop sweep prompt + cadence guidance
    └── signal-template.md            # signal frontmatter + body template
```

## TL;DR to spin up on a fresh vault
```bash
cd /path/to/vault
bash lodestar/bootstrap-lodestar.sh                 # scaffold the bus
# fill prompts/*-goal-prompt.md → specs/active/ops/goals/<agent>-goal-prompt.md
git add specs/active/ops lodestar
git commit -m "chore(stable): bootstrap coordination bus"
git push
# then, per RUNBOOK.md: open a claude session per agent, /goal (paste its goal),
# /loop (start its heartbeat). One orchestrator + N workers.
```


## The five ideas that make it work
1. **Git is the only state.** Not committed+pushed = invisible. Pull before
   thinking; push the moment you commit.
2. **Files are the bus.** signals/ (queue), SCRATCHPAD (messages), BLOCKERS
   (dependencies), goals/ (identity). All durable, all auditable.
3. **Agents are stateless + idempotent.** Every wake is the same loop. A
   respawned agent ≡ one that never died.
4. **Lanes prevent collisions.** One PREFIX per worker; never `git add -A`; one
   writer per signal.
5. **Verify live, never assume.** "Merged" ≠ "deployed" ≠ "works." Only a
   real-path check closes a signal. Gate on real events, never elapsed time.
