# Signal template

A signal = one unit of work. One file per signal: `<OPS>/signals/<PREFIX>-<N>.md`.
The frontmatter is the machine-readable contract; the body is for the human +
the agent that picks it up. Copy the block below.

```markdown
---
id: <PREFIX>-<N>
team: <worker-lane>            # which worker owns this
status: READY                  # READY | CLAIMED | IN_PROGRESS | DEPLOYED | DONE | BLOCKED | DEFERRED | SUPERSEDED
owner:                         # set to the worker name on claim
blocked_by:                    # name the blocking signal/blocker if BLOCKED; "—" if none
unblocks:                      # what this enables downstream (helps prioritize)
audit_ref:                     # where this came from (operator request, audit, sweep)
priority: <P0|P1|P2> — <one-line why>
loop_mode: continuous          # or per_iteration
cleanup_paths_provided: yes    # how to revert if this goes wrong
---

# <PREFIX>-<N> — <short title>

## What
<Precise description. If a bug: the root cause with evidence (file:line, log line,
live-state finding) — not a theory. If a feature: the exact change + flow.>

## Why
<Why this matters / what breaks without it. Link the upstream request or finding.>

## Files / touch points
<Exact files, repos, stacks, secrets, IAM the worker will touch.>

## Acceptance test
<The REAL-PATH check that closes this signal. Prefer a live probe / real user
action over a mocked test — "the deploy went green" is not acceptance. State who
verifies and how.>

## Notes
<Gotchas, related memories/feedback, sequencing constraints, eliminate-the-
operator-step considerations.>

## Activity log
- <date> — filed by <who> (<context>). <one-line summary>.
```

## Status semantics (be strict)

- **READY** — actionable now, unclaimed.
- **CLAIMED** — a worker took it (set `owner`), not yet shipping code.
- **IN_PROGRESS** — code in flight (PR open / CI running).
- **DEPLOYED** — merged + deployed, awaiting the live acceptance check.
- **DONE** — acceptance test passed LIVE. The only terminal "success" state.
- **BLOCKED** — can't proceed until a named `blocked_by` (another signal) or a
  hard external-event gate clears. Must name the trigger. Use this for "engineering
  done, waiting on a real external event that can't be faked" (e.g. validates only
  on the first real user's first event). Reconsider every cycle.
- **DEFERRED** — **rare.** Only for an explicit *operator* decision to park ("skip
  this for now, my call") or a signal superseded-by-an-event. **NOT for
  priority-parking** — see the rule below.
- **SUPERSEDED** — replaced by another signal (name it).

> **Priority is for ordering; status is for reality.** Do NOT use DEFERRED to
> "park for later because something else is hotter." That hides the work from
> signal-driven loops (a worker sweeps READY signals; a DEFERRED one falls off
> its radar — a drained lane then idles on a backlog it can't see). Instead:
> a non-urgent signal is a **low-priority READY** (P2), re-ordered behind the hot
> work but still visible. A hard external gate is **BLOCKED with a named trigger**.
> The only legitimate DEFERRED is an explicit operator park. (`feedback_no_defer_only_reprioritize`)

## Anti-patterns to avoid

- Marking DONE on "merged" or "deployed" without a live check (`feedback_no_seed_data`).
- A "definitive fix" commit that's actually partial — audit the mechanism vs.
  the live state before trusting it (`feedback_partial_fix_audit`).
- A cross-team flow filed as ONE lane's signal with the other lanes as footnotes
  — file a signal per touched lane.
- **Parking work in DEFERRED because it's not the top priority.** Use low-priority
  READY (re-order, don't hide). DEFERRED hides work from the owning loop.
- A time-gated / "soak N days" acceptance criterion — gate on a real event
  (real user/customer activity), never elapsed time.
```
