# Lodestar — Orchestrator + Worker Runbook

A reset-proof, vault-agnostic pattern for running an **orchestrator** agent that
coordinates one or more **worker** agents through committed files. The git repo
*is* the shared memory and message bus; agents are stateless processes that
reconstitute their entire working context from disk on every wake. Any single
agent can be killed and respawned from a cold context with zero loss — it reads
the files and continues.

> "Karpathy-style": the model is a stateless function; all state lives in the
> environment (here, the git-tracked vault). Context resets are non-events.

---

## 0. Mental model (read first)

- **Source of truth = the git repo.** Not any agent's context window. If it
  isn't committed, it doesn't exist.
- **Coordination bus = files**, in `<OPS>/` (default `specs/active/ops/`):
  - `signals/<PREFIX>-<N>.md` — one unit of work each (the work queue).
  - `SCRATCHPAD.md` — async cross-agent threads (the message bus).
  - `BLOCKERS.md` — cross-cutting blockers (the dependency ledger).
  - `<agent>-goal-prompt.md` — each agent's durable mission (its identity).
- **Agents are stateless + idempotent.** Every wake: `git pull` → read bus →
  do the smallest useful thing → commit → push → sleep. A respawned agent is
  indistinguishable from one that never died.
- **Lanes prevent collisions.** Each worker owns a signal PREFIX (e.g. `INFRA-*`)
  and a set of repos/stacks. Workers never edit another lane's signals or repos.
- **The operator (you) is the only human gate.** Agents surface operator
  actions explicitly and triage "can we eliminate this?" before asking.

---

## 1. One-time setup per vault

Run the bootstrap once in a fresh vault (or to add Lodestar to an existing one):

```bash
cd /path/to/your-vault
bash lodestar/bootstrap-lodestar.sh        # idempotent — safe to re-run
```

This scaffolds `<OPS>/` with `SCRATCHPAD.md`, `BLOCKERS.md`, a `signals/`
dir + `_TEMPLATE.md`, and a `goals/` dir. Commit + push the scaffold.

Decide your **lanes** up front. A lane = (PREFIX, repos, stack, exceptions).
Example:

| Agent      | Prefix     | Repos / stack                       |
|------------|------------|-------------------------------------|
| orchestrator | (none)   | the vault only (writes bus files)   |
| infra      | `INFRA-*`  | infra repo + IaC stack              |
| app        | `APP-*`    | the app repo                        |

---

## 2. Spinning up an ORCHESTRATOR

The orchestrator owns the bus, not the code. It sweeps for movement, keeps the
ledger honest, routes work, and surfaces operator actions.

1. **On its machine/container**, clone (or NFS-mount) the vault and verify git
   identity + push access (see §5 git-sync).
2. Open a `claude` session in the vault root.
3. **Set its mission** with `/goal`, pasting `lodestar/prompts/orchestrator-goal-prompt.md`
   (fill the `<PLACEHOLDERS>` — vault path, OPS path, worker list).
4. **Start its loop** with `/loop` (dynamic, self-pacing) or `/loop 5m <prompt>`
   for a fixed cadence. See `lodestar/prompts/loop-prompt.md`.
5. The orchestrator now wakes on its heartbeat, sweeps, and acts.

The orchestrator does **not** edit worker repos, run deploys, or merge worker
PRs. It writes vault bus files only. (Tighten/loosen in its goal's Authorization
block.)

---

## 3. Spinning up a WORKER

A worker owns one lane: it drains its signal queue, ships code, deploys its
stack, and reports.

1. **On its machine/container**, clone (or NFS-mount) the vault. Also clone the
   worker's target repo(s) if separate from the vault.
2. Open a `claude` session in the vault root (so it can read the bus).
3. **Set its mission** with `/goal`, pasting `lodestar/prompts/worker-goal-prompt.md`
   with placeholders filled for this lane (PREFIX, repos, stack, auth exceptions).
4. **Start its loop** with `/loop 5m <sweep prompt>` (workers usually want a
   steady cadence) or dynamic. See `lodestar/prompts/loop-prompt.md`.
5. The worker wakes, pulls, drains its lane, commits + pushes, sleeps.

To add a second worker: repeat with a different PREFIX. To respawn a dead
worker: just do steps 2-4 again — it reconstitutes from the bus.

---

## 4. The per-wake loop (every agent, every cycle)

This is the heartbeat contract. Both orchestrator and workers follow it:

```
1. git pull --ff-only                      # sync the bus + repos
2. Read SCRATCHPAD top + BLOCKERS open      # what's new / what's stuck
3. Sweep my lane's signals (workers) OR all lanes (orchestrator)
4. Do the SMALLEST useful next action       # one signal, one fix, one route
5. Update the relevant file(s) (signal status / SCRATCHPAD / BLOCKERS)
6. git add <specific files> && commit && push   # NEVER `git add -A` blindly
7. If a human gate is needed: surface it (🟡) with triage
8. Sleep until next heartbeat (re-arm /loop)
```

Idle is fine. If nothing moved and nothing's actionable, **skip the busywork**,
post no digest, and sleep. Manufacturing no-op commits to "look busy" is the
anti-pattern.

---

## 5. Git-sync protocol (the load-bearing discipline)

See `lodestar/GIT-SYNC.md` for the full protocol. The essentials:

- **Every wake starts with `git pull --ff-only`.** Never operate on stale state.
- **Commit only the files you touched.** `git add <explicit paths>`, never
  `git add -A` — other agents/editors share the tree.
- **Push immediately after commit.** Unpushed commits don't reach other agents
  (and on separate machines, don't sync at all). A commit without a push is
  invisible work.
- **Conflicts:** the bus files (SCRATCHPAD/BLOCKERS) are append-at-top and
  small; on a conflict, `git pull --rebase`, re-read, re-apply your edit at the
  new top. Signals are one-file-per-unit so they rarely collide across lanes.
- **Identity per host.** Each machine/container sets `git config user.name` to
  the agent's name (e.g. `infra-claude`) so the history shows who did what.
- **One writer per signal.** A signal is owned by its lane; only that lane's
  worker flips its status. The orchestrator may correct stale status but says so.

---

## 6. The signal lifecycle

```
READY → CLAIMED → IN_PROGRESS → DEPLOYED → DONE
   ↑                               ↘ BLOCKED (named blocked_by / external-event trigger)
(low-pri P2 = not-urgent,           ↘ DEFERRED (operator park ONLY — rare)
 re-ordered not hidden)
```

- A worker **claims** a READY signal (sets owner + status), works it, ships,
  **verifies live**, then flips DONE. "Merged" ≠ "deployed" ≠ "verified" —
  only a real-path check closes a signal (see `feedback_no_seed_data`).
- **BLOCKED** names a `blocked_by` signal OR a hard external-event trigger
  (engineering done, waiting on a real event that can't be faked).
- **Don't park work in DEFERRED because it's lower priority** — that hides it
  from the owning loop (which sweeps READY). Use a **low-priority READY** and
  re-order. DEFERRED is reserved for an explicit *operator* park.
  (`feedback_no_defer_only_reprioritize`)
- The orchestrator audits: a signal claiming DONE whose deploy actually failed
  gets re-opened. Trust the live system, not the commit message.

---

## 7. Operator (human) actions

Agents surface operator actions in their status with a 🟡 marker, but **only
after triaging "can we eliminate this?"** Many "operator-only" steps dissolve
when re-expressed as IaC the agent can run. Genuine operator actions:
- creating external accounts/apps with no API (e.g. a GitHub App),
- one-time trust-root credentials the automation can't bootstrap,
- security-weakening changes that need explicit human approval,
- registering external webhooks / seeding secrets you hold.

When surfacing one, give the **exact command/click**, not a vague ask.

---

## 8. Failure & recovery

| Failure | Recovery |
|---|---|
| Agent context reset | Respawn: `/goal` (paste its goal file) + `/loop`. It reads the bus + continues. Zero special handling. |
| Agent process dies | Same — respawn from its goal file. |
| Two agents edited the same file | `git pull --rebase`, re-apply. Bus files are designed to merge. |
| A worker's lane is stuck | Orchestrator surfaces it (with the exact fix) after N idle cycles. |
| Whole fleet idle | Check each agent's loop is actually firing; restart loops. The bus state is intact regardless. |

---

## 9. Files in this kit

- `RUNBOOK.md` — this file.
- `GIT-SYNC.md` — the full git discipline.
- `bootstrap-lodestar.sh` — idempotent scaffolder for a new vault.
- `prompts/orchestrator-goal-prompt.md` — orchestrator `/goal` template.
- `prompts/worker-goal-prompt.md` — worker `/goal` template.
- `prompts/loop-prompt.md` — the `/loop` sweep prompt template.
- `prompts/signal-template.md` — the signal frontmatter + body template.
