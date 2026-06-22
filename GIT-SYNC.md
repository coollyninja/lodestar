# Git-Sync Protocol

The vault git repo is the shared memory and message bus. When orchestrator and
workers run on **separate machines/containers**, git is the *only* thing keeping
them in sync — so this discipline is load-bearing, not optional. (If they share
a filesystem via NFS/host-mount, git still governs ordering + history; the rules
below all still apply.)

---

## The invariant

> An agent's durable state = what is committed AND pushed to `origin`.
> Anything in a context window or an unpushed commit is invisible to the fleet.

Two corollaries:
1. **Pull before you think.** Always `git pull --ff-only` at the top of a wake.
2. **Push the moment you commit.** A commit without a push is lost work on a
   separate-machine topology.

---

## Per-wake sequence (canonical)

```bash
# 1. SYNC IN — fast-forward only; never auto-merge garbage
git pull --ff-only origin "$BRANCH" || {
  # someone pushed concurrently — rebase your local (you have none yet this wake)
  git pull --rebase origin "$BRANCH"
}

# 2. ... read bus, do work, edit specific files ...

# 3. SYNC OUT — stage ONLY what you touched
git add <explicit/paths/you/edited.md> ...      # NEVER `git add -A`
git commit -m "<conventional msg>"
git push origin "$BRANCH" || {
  # lost the race: someone pushed between your pull and push
  git pull --rebase origin "$BRANCH"            # replay your commit on top
  git push origin "$BRANCH"
}
```

The `pull --rebase` + retry on push failure handles the only real race:
two agents committing in the same window. Because each agent touches different
files (different signals / append-at-top bus files), rebase almost always
applies cleanly with no conflict.

---

## Staging discipline (the #1 footgun)

**Never `git add -A` / `git add .`.** The working tree is shared by multiple
agents, human editors, linters, and sometimes nested repos. Blind staging:
- sweeps in another agent's half-finished edit,
- commits generated/secret files,
- creates phantom diffs.

Always `git add` the **explicit paths** you edited. Before committing, run
`git status -sb` and confirm the staged set is exactly yours.

---

## Conflict handling for the bus files

`SCRATCHPAD.md` and `BLOCKERS.md` are the only files multiple agents append to.
They're designed to merge:

- **SCRATCHPAD.md** — new threads go at the **top** of `## Active threads`.
  On a conflict: `git pull --rebase`, re-read the new top, re-insert your thread
  above it. Never delete another agent's thread to resolve.
- **BLOCKERS.md** — small table; rows are append/edit. On conflict, rebase and
  re-apply your single row change.
- **signals/<X>.md** — one file per unit, owned by one lane → cross-lane
  collisions are structurally near-impossible. Same-lane: one worker owns the
  lane, so no concurrency.

If a rebase conflict is ever non-trivial, STOP and surface it rather than
force-resolving — a bad merge of the bus corrupts coordination for everyone.

---

## Identity per host

Each machine/container sets git identity to the agent it runs:

```bash
git config user.name  "infra-claude"          # or orchestrator-claude, etc.
git config user.email "infra-claude@<your-domain>"
```

This makes `git log` an audit trail of which agent did what — invaluable when
debugging "who changed this signal."

End commit messages with a consistent co-author trailer so automation/history
is attributable, e.g.:

```
<subject>

<body>

Co-Authored-By: lodestar <ops@your-domain>
```

---

## Worker repos vs. the vault

A worker syncs **two** things:
1. **The vault** (the bus) — pull/commit/push per above for signal + SCRATCHPAD
   updates.
2. **Its target repo(s)** (the code it ships) — normal branch/PR/merge flow,
   per that repo's conventions.

Keep them distinct: vault commits track *coordination*; repo commits track
*code*. A worker's wake typically ends with a vault commit (status update) even
when the code work is a separate PR in the target repo.

Branch convention for code work (recommended): `claude/<short-description>`
against the repo's default branch; PR via your platform CLI. Direct-to-main only
for hotfixes or when explicitly authorized.

---

## Separate-machine specifics

- **Clone, don't assume a shared FS.** Each host `git clone <remote>` into its
  own working dir. NFS/host-mount is an option but not required — git over the
  remote is the portable baseline.
- **SSH keys / tokens per host.** Each machine needs push credentials. Use a
  deploy key or a scoped token per agent host; never share one human's
  credentials across all agents if you can avoid it (breaks the audit trail).
- **Clock skew is irrelevant** — git ordering is by commit graph, not
  timestamps. But do set timezones consistently so log reading isn't confusing.
- **The remote is the rendezvous.** Two agents that never share an FS still
  coordinate perfectly as long as both can reach `origin`. That's the whole
  trick.

---

## Health check (run anytime)

```bash
git fetch origin && git status -sb        # am I behind/ahead? clean tree?
git log --oneline -5                       # recent fleet activity
git log --oneline origin/$BRANCH -5        # what's actually on the remote
```

If `ahead N` persists, you have unpushed work — push it. If `behind N`
persists, you're operating on stale state — pull.
