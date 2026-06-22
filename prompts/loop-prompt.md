# /loop sweep prompt template

The `/goal` sets the durable mission; `/loop` drives the recurring heartbeat.
Use the matching sweep prompt below. The `/loop` skill self-paces (dynamic) or
takes a fixed interval as a leading token (`/loop 5m <prompt>`).

---

## Orchestrator loop prompt

Paste after `/loop ` (dynamic) or `/loop 5m ` (fixed). Replace `<PLACEHOLDERS>`.

```
resume orchestrating Lodestar per <ORCH_NAME> /goal. Sweep vault + worker repos
(<REPO_LIST>) for movement since last cycle. Read SCRATCHPAD top + BLOCKERS.md.
If team-side movement: post one [<ORCH_NAME> → all teams + operator] cycle digest
at TOP of Active threads, commit, push. If no movement: skip digest. Status to
operator with 🟡 at top if any operator action needed; otherwise terse one-liner.
Triage "can we eliminate this?" before surfacing any 🟡. On idle, do not
manufacture busywork — post nothing and sleep.
```

## Worker loop prompt

```
resume working the <PREFIX>-* lane per <WORKER_NAME> /goal. git pull (vault +
<REPOS>). Read SCRATCHPAD threads to me/all + BLOCKERS rows I own. Drain my lane:
blockers before backlog, P0/P1 first; claim → PR → CI → merge → deploy <STACK> →
verify live → flip DONE. Post SCRATCHPAD on landing/new-blocker, commit+push the
status update. If nothing actionable, sleep without a busywork commit.
```

---

## Cadence guidance (dynamic mode)

When self-pacing, pick the heartbeat by what you're waiting on:

| Situation | Delay |
|---|---|
| Active P0 / CI mid-flight | 10-15 min (720-900s) |
| Normal backlog draining | 5-10 min |
| Idle, waiting on an operator action | 20-30 min (1200-1800s) |
| Fleet stopped / nothing actionable | 60 min (3600s) max, or stop the loop |

Don't poll a stopped fleet on a tight cadence — it accomplishes nothing and
burns cache. Re-arm the loop at the END of every wake (including Q&A turns), or
the next wake is orphaned.

## The idle anti-pattern (important)

If your "Done" condition is event-driven on *other* agents (e.g. "all lanes
drained"), a naive loop will fire forever on idle, refusing to rest. Fix: make
each turn's Done a **per-turn predicate** ("I completed this wake's sweep for the
current state"), and treat the mission goal as *monitored*, not *gated*. On a
genuinely idle sweep: post nothing, sleep. Surface the idle to the operator at
most once, not every cycle.
