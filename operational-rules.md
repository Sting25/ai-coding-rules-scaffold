# Operational rules

Process, collaboration, and judgment rules for working effectively
with AI agents (and as a human engineer). These are durable patterns
extracted from real failure modes — not code-level rules (those live
in [`coding-rules.md`](./coding-rules.md)) but session-level
discipline that no linter can enforce.

For Claude Code with the full scaffold, this file is referenced
from `AGENTS.md`, which is auto-loaded via `CLAUDE.md`.

To use this file **standalone** (no linter / hook / CI scaffolding),
drop it in your project root and add `@operational-rules.md` to your
`CLAUDE.md` — that auto-loads it into context on session start. No
`install.sh`, no hooks, no CI workflow needed.

For Cursor, Cline, Aider, or other AI tools, add an equivalent
reference to whatever config file the tool uses (an `alwaysApply: true`
project rule under `.cursor/rules/`, `.clinerules`, `CONVENTIONS.md`,
etc.). The goal is that the agent sees this document at the start of
every session.

If you're using this without an AI agent, the document still works
as a reference for human engineers. Read it before writing code,
revisit it when something goes wrong, add to it when you find a
new failure mode.

---

## Engineering

### Read schema constraints before composing writes

Enum-style columns and check constraints have allowed-value lists
baked into the model. Open the model file and scan constraint blocks
before writing any INSERT, UPDATE, or migration. AI tools frequently
generate plausible-looking values that violate constraints they
didn't see.
_Anchor:_ every per-record INSERT failed because the agent passed a
descriptive string when the schema required a specific enum value
defined elsewhere in the codebase.

### Plan storage shape before scaling compute

For any per-unit output (tile, record, document, embedding), multiply
size by realistic scale before committing to a format. Tiered
retention designed in from day 1, not retrofitted.
_Anchor:_ per-unit output measured at multiple GB; full-scale
projection ran into petabytes. Format and tiering decisions had to
be redone after significant ingestion was already complete.

### Heartbeats must not block on long synchronous I/O

If a worker reports liveness via heartbeats, those heartbeats must
tick from a daemon thread independent of work, OR async I/O must
yield between operations. Synchronous I/O during work blocks the
heartbeat and triggers false-positive reaping.
_Anchor:_ reaper killed workers that were busy with large uploads,
not actually dead, because the heartbeat thread was blocked on the
same synchronous I/O the worker was performing.

### Validate inputs at component boundaries

Each component in a federated or distributed system should validate
its inputs at the boundary, not assume the upstream component honored
the contract. AI-generated code often skips boundary validation
because it trusts the type system or the upstream implementation it
just wrote. Type annotations document structure, they don't enforce
it: tests should both `assert isinstance(...)` AND touch named
attributes — a duck-typed stand-in with wrong fields fails only the
second check.
_Anchor:_ a downstream component crashed on malformed input an
upstream component should have rejected; separately, an orchestrator
returned a 4-tuple where the worker expected a typed dataclass and the
annotation lied. Neither side validated the contract between them.

### Integration tests hit a real database, not mocks

Mocked tests pass against the mock's behavior, not against the
database's actual behavior. Schema constraints, migration drift,
and dialect quirks only surface against a real instance. Spin up
an ephemeral DB per test run if isolation matters — but don't
substitute a mock object for the connection. Run the full pre-prod
check in a throwaway environment built from the same provisioning
script as production, not on a standing QA box that drifts from it.
_Anchor:_ mocked tests passed for months while the production
migration silently broke; the divergence was invisible until a
deploy hit the real schema.

### No silent failures

When a unit of work fails — a request, a record, a cell, a job — log
a WARN-or-higher event with the failure reason AND surface the failure
in the response payload (a `partial` status, an explicit error field,
a non-success HTTP code). Catching an exception and returning a
"success" response without signaling the failure leaves downstream
consumers acting on stale or wrong data, and surfaces hours later as
a derived failure that is harder to trace back.
_Anchor:_ a batch job swallowed per-record errors and reported
"complete"; downstream pipelines built on the missing-rows-without-error
state spent days untangling the resulting derived corruption.

### Fix the file, not the guardrail — don't weaken a check to pass

When a check goes red — a secret/pattern/size/hygiene scan, a lint or
type error, a failing test — fix the offending FILE. Suppressions
(`scaffold-allow`, a `.scaffold.toml` disable/downgrade, a loosened
pattern, a skip-list entry, `--no-verify`) are a last resort: only for
a genuine false positive, only when fixing the file truly isn't
possible, and then narrowly, with a recorded reason, and named in the
summary you give the person you are working for — which check, which
file, which marker or config entry, and why. If the check itself is
wrong, fix the check and add a test; don't bypass it. Deleting is
weakening: removing a test file, a test case, or the CI workflow that
runs them stops the check existing at all, and does it quietly —
nothing goes red. Never delete a test in the same change as the code
it covered; name the test, why it no longer applies, and where the
coverage went. "Removed outdated tests" is not a justification, it is
the sentence that hides one.
_Anchor:_ a guardrail flagged a file; exempting it was one line and
fixing it a few — but an exemption, unlike a fix, never expires, so
suppressions accrete until the scanner no longer scans.

### Choose the strongest approach at the fork, not after the work is built

Decide between the robust approach and the quick one BEFORE writing the
fix. Once the fast path is built, sunk cost decides for you and the
question becomes a postmortem. When speed or simplicity is the only
reason to prefer a path, treat that as a reason to slow down, not a
green light.
_Anchor:_ denylist rules written quickly and checked only for syntax
were then measured against real third-party code: three fired on
legitimate code every time they fired, and had to be deleted after a
full rework round. Measuring first was the same work, once.

### Hold shared-resource locks for contiguous work, not per operation

When multiple processes contend for a single shared resource (GPU,
DB connection from a small pool, hardware port, file lock),
acquire the lock once for the contiguous stretch of work and
release after — never per individual operation. Per-operation
locking causes thrash, partial-state failures under contention,
and starvation when one worker can never acquire long enough to
complete a unit of work.
_Anchor:_ per-CUDA-call GPU lock acquisition caused worker thrash
and out-of-memory failures because no single worker ever held the
lock long enough to complete a contiguous compute unit.

### Never print, cat, or echo secret files

Never `cat`, `print`, `echo`, or log `.env`, `credentials.json`, key
files, or tokens — verify by length, hash, or line count instead;
pattern scanning backs this up only for credential shapes on paths it
already knows.
_Anchor:_ AI-agent-driven `cat .env` to "verify the file is loaded"
landed credentials into a permanent chat transcript; rotation across
multiple services took hours.

### Back up and confirm before destructive work on live data

A `DROP`, a `TRUNCATE`, an unbounded `DELETE` or `UPDATE`, a
migration, or a wipe of a bucket, document collection, or search
index — a "reset the data and start clean" counts — against
anything but a local throwaway store is a two-step action: confirm
a current backup exists, then get an explicit yes that names the
target and what will be lost. Quote the blast radius in the store's
own units — table rows, bucket objects, collection documents — not
as a pasted command. Before any sweeping or multi-step change, tag
a known-good point and name it out loud, rather than committing
whatever is on disk, which the commit gate will reject; an editor's
rewind is not the restore point either, since it never sees what a
shell command moved or deleted.
_Anchor:_ an agent ran a destructive operation against a production
database it believed was a test instance and emptied it in seconds;
there was no staging tier and no recent backup. Another, told to tidy
up branch history, hard-reset away a day of untagged work.

### Assert the positive outcome, not the absence of the symptom

A test that only checks an error string is absent also passes when the
code crashes to empty output. Pair every negative assertion with one
that the wanted artifact was produced (marker emitted, exit 0, file
present).
_Anchor:_ a hook-killing crash sailed through a 1400-assertion suite
because the new regression test asserted only that a warning string
was absent; the crash made it absent too.

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

### Commit each passing unit of work atomically, without waiting for approval

This overrides the generic "never commit unless explicitly asked"
default some tools ship with. On a feature branch or worktree, once a
logical unit of work passes its own gate (tests, lint, the checks the
repo already runs), commit it and move on — one commit per logical
change, grouped only when tightly coupled (a fix plus the test that
prevents its regression). Do not pause mid-task to ask permission for
each commit. Pushing, merging into a protected branch, and
force-pushing still need their own explicit approval every time.
_Anchor:_ mixed commits become unrevertable when one fix turns out to
be wrong; separately, an agent kept asking before each commit on a
branch the user had already scoped and approved the work for, until
told "always do atomic commits, do not wait for me".

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
_Anchor:_ a feature merge bumped to 0.18.0 while the latest tag was
v0.17.0; installs tracking the branch picked up an unreleased version.

### A check that can pass by luck is failing

When a test turns out to be nondeterministic, stop and make it
deterministic before merging anything through it; rerunning until
green is papering over. Treat the first unexplained flake as a defect
with a root cause, not weather.
_Anchor:_ a flaky assertion passed one PR's required CI job and failed
the next identical run minutes later; the two-line fix existed only
because the failure was investigated instead of rerun.

---

## Collaboration

### Agent reports measurements; user calls "fixed" / "done"

Concrete numbers (test counts, throughput, byte sizes, gate pass
rates, latency) come from the agent. Verdicts ("fixed", "done",
"verified", "working") come from the user.

### Close every handoff with a plain-language summary

The artifact that makes the rule above usable. Before handing back a
commit, a PR, or the session itself, state in plain language what
changed and why, anything destructive or hard to reverse, every check
you turned down by name, and what the user should verify before calling
it done. See `AGENTS.md`, "Plain-language change summary", for the full
form; it feeds the verdict, it never delivers it.

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
_Anchor:_ a harness printed "skipped (tool not installed)" on every
runner for months; the check it guarded had never once executed,
and nothing recorded that it wasn't running.

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
_Anchor:_ a PR was merged by a concurrent session no one could later
identify, minutes after another session's audit snapshot; separately, a
duplicate repo checkout was deleted minutes after a concurrent session
had filed an issue from inside it, with the PR-and-mainline check clean.

---

## Adding rules to this document

A rule earns its place when:

- A real incident demonstrated the failure mode
- The fix is generalizable beyond the specific incident
- Tool-enforcement (lint, hooks) can't catch it
- The rule can be stated as an imperative + anchor in under 5 lines

A rule should be retired when:

- The original anchor no longer applies in current tooling
- The pattern has been absorbed into a tool-enforceable rule
- The rule has been superseded by a better-articulated version

Anchors should reference the type of incident, not project-specific
details, so the document remains useful across projects.
