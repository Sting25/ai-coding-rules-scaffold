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
reference to whatever config file the tool uses (`.cursorrules`,
`.clinerules`, `CONVENTIONS.md`, etc.). The goal is that the agent
sees this document at the start of every session.

If you're using this without an AI agent, the document still works
as a reference for human engineers. Read it before writing code,
revisit it when something goes wrong, add to it when you find a
new failure mode.

---

## Engineering

### Pass structured types, not primitive tuples, across boundaries
The structured value is what crosses the wire. Tests should both
`assert isinstance(...)` AND touch named attributes — a duck-typed
stand-in with wrong fields fails the second check. Type annotations
alone don't enforce structure; they only document intent.
*Anchor:* orchestrator returned a 4-tuple where worker expected a
typed dataclass; the type annotation lied and the bug surfaced only
after compute had been spent.

### Read schema constraints before composing writes
Enum-style columns and check constraints have allowed-value lists
baked into the model. Open the model file and scan constraint blocks
before writing any INSERT, UPDATE, or migration. AI tools frequently
generate plausible-looking values that violate constraints they
didn't see.
*Anchor:* every per-record INSERT failed because the agent passed a
descriptive string when the schema required a specific enum value
defined elsewhere in the codebase.

### Use the canonical helper; bench code is bench-only
Before writing math, format, or utility helpers, grep production for
existing implementations. Bench scripts and exploratory notebooks
shortcut things that production must do correctly. AI tools will
happily reach for bench-style patterns when generating production
code if you don't redirect.
*Anchor:* a driver inherited bench-style coordinate math when a
canonical helper already existed in production code; the bench
version had edge-case bugs the canonical version had already fixed.

### Plan storage shape before scaling compute
For any per-unit output (tile, record, document, embedding), multiply
size by realistic scale before committing to a format. Tiered
retention designed in from day 1, not retrofitted. Storage cost
surprises kill more personal projects than any other failure mode.
*Anchor:* per-unit output measured at multiple GB; full-scale
projection ran into petabytes. Format and tiering decisions had to
be redone after significant ingestion was already complete.

### Heartbeats must not block on long synchronous I/O
If a worker reports liveness via heartbeats, those heartbeats must
tick from a daemon thread independent of work, OR async I/O must
yield between operations. Synchronous I/O during work blocks the
heartbeat and triggers false-positive reaping.
*Anchor:* reaper killed workers that were busy with large uploads,
not actually dead, because the heartbeat thread was blocked on the
same synchronous I/O the worker was performing.

### Validate inputs at component boundaries
Each component in a federated or distributed system should validate
its inputs at the boundary, not assume the upstream component
honored the contract. AI-generated code often skips boundary
validation because it trusts the type system or the upstream
implementation it just wrote.
*Anchor:* a downstream component crashed on malformed input that an
upstream component should have rejected; both components were
AI-generated and neither validated the contract between them.

### Integration tests hit a real database, not mocks
Mocked tests pass against the mock's behavior, not against the
database's actual behavior. Schema constraints, migration drift,
and dialect quirks only surface against a real instance. Spin up
an ephemeral DB per test run if isolation matters — but don't
substitute a mock object for the connection.
*Anchor:* mocked tests passed for months while the production
migration silently broke; the divergence was invisible until a
deploy hit the real schema.

### Tests cover every code path; back claims with measurement
"We have tests" is not the same as "this is tested." Every branch,
every error path, every contract assertion needs an explicit test.
When claiming correctness or performance, back the claim with a
number from a real run against a real system — not a narrative
about what the code "should" do.
*Anchor:* untested code paths routinely shipped with undiscovered
bugs that surfaced as production incidents months after merge,
because "looks right" beat "measured to work."

### No silent failures
When a unit of work fails — a request, a record, a cell, a job —
log a WARN-or-higher event with the failure reason AND surface the
failure in the response payload (e.g. via a `partial` status,
explicit error field, or non-success HTTP code). Catching an
exception and returning a "success" response without signaling
the failure is the most expensive habit in production code;
downstream consumers act on stale or wrong data, and the problem
only surfaces hours later as a derived failure that's harder to
trace back.
*Anchor:* a batch job swallowed per-record errors and reported
"complete"; downstream pipelines built on the missing-rows-without-error
state spent days untangling the resulting derived corruption.

### Hold shared-resource locks for contiguous work, not per operation
When multiple processes contend for a single shared resource (GPU,
DB connection from a small pool, hardware port, file lock),
acquire the lock once for the contiguous stretch of work and
release after — never per individual operation. Per-operation
locking causes thrash, partial-state failures under contention,
and starvation when one worker can never acquire long enough to
complete a unit of work.
*Anchor:* per-CUDA-call GPU lock acquisition caused worker thrash
and out-of-memory failures because no single worker ever held the
lock long enough to complete a contiguous compute unit.

### Never print, cat, or echo secret files
`.env` files, `credentials.json`, key files, OAuth tokens — never
`cat`, `print`, `echo`, or log them. AI agents have a particular
habit of running `cat .env` during debugging "to check something";
the values then live in chat transcripts, log files, or git
diffs forever and require rotation. To verify a value exists or
matches an expected shape: check length, compare against a known
hash, or count non-empty lines. The cheapest path is never to
expose the secret in the first place.
*Anchor:* AI-agent-driven `cat .env` to "verify the file is
loaded" landed credentials into a permanent chat transcript;
rotation across multiple services took hours.

---

## Process

### One canonical decisions file; archive everything else
All locked decisions live in a single file (`CURRENT.md`,
`DECISIONS.md`, or similar). Old files move to `_archive/`. New
decisions update the canonical file, not new files. AI agents take
shortcuts when reading everything isn't tractable, so the canonical
file must be loadable into context.
*Anchor:* project accumulated dozens of decision documents and
memory entries; agent began making decisions inconsistent with
locked ones because it couldn't read everything in a single pass.

### Pre-flight catches beat mid-run discovery
For any job longer than 5 minutes wall-clock, write a pre-flight
check per external dependency. Fail fast in seconds before committing
to compute. Database reachable? Schema migrated? API auth valid?
Disk space? Output bucket writable?
*Anchor:* pre-flight check caught an unmigrated database and an
unreachable bucket in seconds; would have wasted 38 minutes
mid-run discovering the same problems.

### Smoke at the smallest scale that exercises the full path
After any non-trivial change, run 1 unit / 1 batch / 1 record first.
Scale only after small succeeds. Note the qualifier: smoke tests
that don't exercise the full path are theater. The smoke test must
hit every component that fails at scale.
*Anchor:* a 4-unit smoke caught contention between workers; a
1-unit smoke proved the fix. Both were necessary. A test that
skipped any component would have failed to catch the bug.

### Commit each fix immediately; don't batch
Each logical fix is its own commit. Group only when tightly coupled
(a fix plus the test that prevents its regression). AI tools love
to batch fixes into larger diffs because each individual change
feels small and the cumulative work feels productive.
*Anchor:* mixed commits become unrevertable when one fix turns out
to be wrong; pre-commit failures force re-stage cycles when many
unrelated changes are batched together.

### Locked decisions are revisitable on new evidence
Surfacing new evidence and proposing a revisit IS appropriate.
Re-litigating with the SAME evidence the lock was made with is not.
Classify new evidence: was it available at lock time? load-bearing
on the original decision? strategy update or full unlock?
*Anchor:* a format decision was locked before per-unit size was
measured; the measurement constituted real challenge evidence, not
noise, and warranted explicit revisit rather than silent override.

### Write down why, not just what
Code comments and decision documents should explain why a choice
was made, not just what the code does. AI tools regenerate "what"
on demand from any "why." Without "why," future sessions can't
distinguish load-bearing decisions from incidental ones.
*Anchor:* a refactor session removed a workaround whose reason had
never been written down; the original bug returned weeks later
and required rediscovery from scratch.

---

## Collaboration

### Agent reports measurements; user calls "fixed" / "done"
Concrete numbers (test counts, throughput, byte sizes, gate pass
rates, latency) come from the agent. Verdicts ("fixed", "done",
"verified", "working") come from the user. AI tools tend to declare
victory based on surface pattern matching rather than verified
behavior; reserving the verdict for the human prevents premature
"fixed" claims.

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

### Capture pre-existing issues; never silently drop them
The complement to scope discipline: "out of scope" means don't
silently EXPAND the change — it does NOT mean pretend you didn't
see it. A pre-existing bug, drift, lint finding, or stale doc
noticed while doing something else MUST land somewhere durable —
a tracked fix-list, an issue, a flagged task — even when it won't
be fixed now. Then let the human decide fix-now vs. later. Dropping
it because "that's not what we're working on" is how known defects
rot in place.
*Anchor:* a session noticed a pre-existing lint finding, labeled it
"out of scope," and moved on; with nothing tracking it, it was
forgotten until it resurfaced later as a failure.

### Surface uncertainty rather than guessing
When the agent doesn't have enough context to make a decision
confidently, the right move is to ask, not to guess and proceed.
Confident-sounding wrong answers are more expensive than honest
"I'm not sure, here's what I'd need to know" responses.

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
