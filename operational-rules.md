# Operational rules

Judgment and collaboration rules for working with AI agents. Rules
about the code live in [`coding-rules.md`](./coding-rules.md); repo
mechanics and red lines (checks, git, destructive actions, secrets,
the change summary) live in [`AGENTS.md`](./AGENTS.md). This file
never restates them.

---

## Engineering

### Fix the file, not the guardrail

`AGENTS.md` > "Checks" says when a suppression is allowed and that it
gets named. The judgment behind it: if the check itself is wrong, fix
the check and add a test. When a test is deleted, name it, why it no
longer applies, and where its coverage went; "removed outdated tests"
is the sentence that hides one.
_Anchor:_ a guardrail flagged a file; exempting it was one line and
fixing it a few — but an exemption, unlike a fix, never expires, so
suppressions accrete until the scanner no longer scans.

### Choose the strongest approach at the fork, not after the work is built

Decide between the robust approach and the quick one BEFORE writing the
fix. Once the fast path is built, sunk cost decides for you and the
question becomes a postmortem. When speed or simplicity is the only
reason to prefer a path, treat that as a reason to slow down, not a
green light.

---

## Process

### One durable home per kind of state

Open work (tasks, bugs, follow-ups) lives in one place and locked
decisions in another; everything else holds pointers to them, never a
second live list. Prune items when they close, resurface every open
one at session start however old, and keep the state an agent must
obey small enough to load in a single pass — an agent that cannot read
all of it takes shortcuts and decides against what is already locked.
_Anchor:_ a project accumulated dozens of decision documents and kept
work state in three places; the agent made decisions inconsistent with
locked ones, finished items were never pruned, open ones were never
resurfaced, and a session scratchpad became a third divergent copy.

### Pre-flight catches beat mid-run discovery

For any job longer than 5 minutes wall-clock, write a pre-flight
check per external dependency. Fail fast in seconds before committing
to compute. Database reachable? Schema migrated? API auth valid?
Disk space? Output bucket writable?
_Anchor:_ pre-flight check caught an unmigrated database and an
unreachable bucket in seconds; would have wasted 38 minutes
mid-run discovering the same problems.

### Smoke at the smallest scale that exercises the full path

After any non-trivial change, run 1 unit / 1 batch / 1 record first.
Scale only after small succeeds. Note the qualifier: smoke tests
that don't exercise the full path are theater. The smoke test must
hit every component that fails at scale.
_Anchor:_ a 4-unit smoke caught contention between workers; a
1-unit smoke proved the fix. Both were necessary. A test that
skipped any component would have failed to catch the bug.

### Locked decisions are revisitable on new evidence

Surfacing new evidence and proposing a revisit IS appropriate.
Re-litigating with the SAME evidence the lock was made with is not.
Classify new evidence: was it available at lock time? load-bearing
on the original decision? strategy update or full unlock?
_Anchor:_ a format decision was locked before per-unit size was
measured; the measurement constituted real challenge evidence, not
noise, and warranted explicit revisit rather than silent override.

### Write down why, not just what

Code comments and decision documents should explain why a choice was
made, not just what the code does. AI tools regenerate "what" on
demand from any "why"; without the why, future sessions can't
distinguish load-bearing decisions from incidental ones.
_Anchor:_ a refactor session removed a workaround whose reason had
never been written down; the original bug returned weeks later.

### Version bumps travel only in release commits

A feature PR that bumps the version strands the mainline on an
unreleased number the moment it merges, and consumers that track the
branch install untagged builds. For a published package, the bump,
changelog heading, tag, and release move together in a dedicated
release change; a dependency's pinned version is an ordinary bump.

### A check that can pass by luck is failing

When a test turns out to be nondeterministic, stop and make it
deterministic before merging anything through it; rerunning until
green is papering over. Treat the first unexplained flake as a defect
with a root cause, not weather.

---

## Collaboration

### Agent reports measurements; user calls "fixed" / "done"

Concrete numbers (test counts, throughput, byte sizes, gate pass
rates, latency) come from the agent. Verdicts ("fixed", "done",
"verified", "working") come from the user. The handoff carrying them
is `AGENTS.md` > "Plain-language change summary".

### Plans default to PROPOSED; mark every assumption

Each value the agent picked itself gets PROPOSED plus a one-line
"alternative would be Y because Z." User scans, redirects where
needed, accepts the rest. Cheaper than a multi-question pre-survey
and more honest than presenting decisions as facts.

### Pause signals stop work, surface state, ask

Words like "hold on" / "wait" / "hmm" / "actually" mean the user
spotted something the agent missed but hasn't articulated yet.
Finish the in-flight edit, summarize current state, ask the
question that prompted the pause. Don't barrel through pauses
treating them as conversational noise.

### Ask before expanding scope

A request to fix bug A is not permission to refactor module B,
even if module B looks improvable. Surface the proposed scope
expansion as a separate question. Scope creep within a single
change is one of the most common ways AI-assisted edits introduce
unintended regressions.

### Capture what you notice and what you defer; never drop it silently

"Out of scope" means don't silently EXPAND the change — it does NOT
mean pretend you didn't see it. A pre-existing bug, drift, lint
finding, or stale doc you noticed, and every skipped test, check that
no-op'd because its tool was absent, unanswered question, workaround
taken "for now", or scope deliberately not taken, lands somewhere
durable AT THE MOMENT it happens — an issue, a tracked fix-list, a
TODO with an owner — with why and what would unblock it; then the
human decides fix-now vs. later. Chat is not durable, and a PR
description counts only if the item also exists outside it.
_Anchor:_ a check reported "skipped" on every run for months and never
once executed.

### One writer per repo at a time; check before merging

Before merging or releasing, re-fetch and check for other active
sessions' open PRs and recent mainline movement. A second writer
merging mid-orchestration invalidates in-flight audits and can leave
provenance untraceable after the fact. Deleting, moving, or repointing
a path another session may be using (a checkout, a worktree, a symlink
target) is a merge-grade write that the PR-and-mainline check cannot
see: read the signals you can — issues or commits freshly filed from
that path, recent file mtimes, open handles or processes. Any positive
signal means stop and ask; true idleness is unprovable, so with no
signals the bar is an explicit go-ahead naming the path, and prefer a
rename over an immediate hard delete so a late writer fails loudly
instead of by luck.
