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

### Pass structured types, not primitive tuples, across boundaries

The structured value is what crosses the wire. Tests should both
`assert isinstance(...)` AND touch named attributes — a duck-typed
stand-in with wrong fields fails the second check. Type annotations
alone don't enforce structure; they only document intent.
_Anchor:_ orchestrator returned a 4-tuple where worker expected a
typed dataclass; the type annotation lied and the bug surfaced only
after compute had been spent.

### Read schema constraints before composing writes

Enum-style columns and check constraints have allowed-value lists
baked into the model. Open the model file and scan constraint blocks
before writing any INSERT, UPDATE, or migration. AI tools frequently
generate plausible-looking values that violate constraints they
didn't see.
_Anchor:_ every per-record INSERT failed because the agent passed a
descriptive string when the schema required a specific enum value
defined elsewhere in the codebase.

### Use the canonical helper; bench code is bench-only

Before writing math, format, or utility helpers, grep production for
existing implementations. Bench scripts and exploratory notebooks
shortcut things that production must do correctly. AI tools will
happily reach for bench-style patterns when generating production
code if you don't redirect.
_Anchor:_ a driver inherited bench-style coordinate math when a
canonical helper already existed in production code; the bench
version had edge-case bugs the canonical version had already fixed.

### Plan storage shape before scaling compute

For any per-unit output (tile, record, document, embedding), multiply
size by realistic scale before committing to a format. Tiered
retention designed in from day 1, not retrofitted. Storage cost
surprises kill more personal projects than any other failure mode.
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
its inputs at the boundary, not assume the upstream component
honored the contract. AI-generated code often skips boundary
validation because it trusts the type system or the upstream
implementation it just wrote.
_Anchor:_ a downstream component crashed on malformed input that an
upstream component should have rejected; both components were
AI-generated and neither validated the contract between them.

### Integration tests hit a real database, not mocks

Mocked tests pass against the mock's behavior, not against the
database's actual behavior. Schema constraints, migration drift,
and dialect quirks only surface against a real instance. Spin up
an ephemeral DB per test run if isolation matters — but don't
substitute a mock object for the connection.
_Anchor:_ mocked tests passed for months while the production
migration silently broke; the divergence was invisible until a
deploy hit the real schema.

### Ephemeral environments replace a standing QA server

Always test against a real database, never synthetic-only fixtures for
anything load-bearing, and always do that testing inside a throwaway
environment (a spun-up container, VM, or short-lived cloud host) rather
than a persistent QA server. Stand it up, run the full pre-prod check,
tear it down. A persistent QA server drifts from production configuration
over time and becomes a second thing to maintain; an ephemeral one is
defined by the same provisioning script that builds production, so it
cannot drift.
_Anchor:_ a search-index rework needed Linux-only measurements (systemd
unit verification, anonymous-memory RSS) that a macOS dev machine could
never produce; the fix was a disposable host built from the same
provisioning script as production, checked and destroyed, not a
standing QA box.

### Tests cover every code path; back claims with measurement

"We have tests" is not the same as "this is tested." Every branch,
every error path, every contract assertion needs an explicit test.
When claiming correctness or performance, back the claim with a
number from a real run against a real system — not a narrative
about what the code "should" do.
_Anchor:_ untested code paths routinely shipped with undiscovered
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
_Anchor:_ a batch job swallowed per-record errors and reported
"complete"; downstream pipelines built on the missing-rows-without-error
state spent days untangling the resulting derived corruption.

### Fix the file, not the guardrail — don't weaken a check to pass

When a check goes red — a secret/pattern/size/hygiene scan, a lint
or type error, a failing test — the default is to fix the offending
FILE, not to weaken the check. Suppressions (`scaffold-allow`, a
`.scaffold.toml` disable/downgrade, a loosened pattern, a skip-list
entry, `--no-verify`) are a last resort: only for a genuine false
positive AND only when fixing the file truly isn't possible, and
then narrowly and with a recorded reason. A check weakened to turn
green silently lowers the bar for every later commit and every
consumer that inherits it — catching the thing was the point. If the
check itself is wrong, fix the check and add a test; don't bypass it.
Deleting is weakening: removing a test file, a test case, or the CI
workflow that runs them is the same offence as loosening a check,
and a quieter one — nothing goes red, the check stops existing, and
the diff reads as cleanup. Name the test, why it no longer applies,
and where the coverage went.
When you do take one, name it in the summary you give the person you
are working for: which check, which file, which marker or config
entry, and why. A one-line suppression is invisible to anyone not
reading the diff, and the person deciding whether it was justified
is usually not reading the diff.
_Anchor:_ a guardrail flagged a file; exempting it was one line and
fixing it a few — but an exemption, unlike a fix, never expires, so
suppressions accrete until the scanner no longer scans.

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

### Choose the strongest approach before starting, not the fastest one to finish

Decide between the correct/robust approach and the quick one BEFORE
writing the fix, not after. By the time work is done and under review,
the fast path is already built and sunk cost pushes toward keeping it;
the decision has to happen at the fork, not as a postmortem question.
When speed or simplicity is the only reason to prefer one path over
another, treat that as a reason to slow down and pick the stronger one,
not a green light to proceed.
_Anchor:_ restated explicitly and independently across multiple
sessions as a standing directive, not tied to one incident: the fast
path (first approach tried, workaround over root cause, suppression
over fix) keeps winning by default unless it's weighed against a
stronger alternative before work begins, since after the fact only a
redo can fix a fast-but-wrong choice already shipped.

### Never print, cat, or echo secret files

`.env` files, `credentials.json`, key files, OAuth tokens — never
`cat`, `print`, `echo`, or log them. AI agents have a particular
habit of running `cat .env` during debugging "to check something";
the values then live in chat transcripts, log files, or git
diffs forever and require rotation. To verify a value exists or
matches an expected shape: check length, compare against a known
hash, or count non-empty lines. The cheapest path is never to
expose the secret in the first place.
_Anchor:_ AI-agent-driven `cat .env` to "verify the file is
loaded" landed credentials into a permanent chat transcript;
rotation across multiple services took hours.

### Create a restore point before risky work

Before a sweeping or multi-step change, tag or branch a
known-good point and name it out loud. Confirming a destructive
command is not the same as being able to get back: the
confirmation happens once, the restore point survives the
mistake. Tag a green point rather than committing whatever is
on disk, which the commit gate will reject. An editor's rewind
feature is not the restore point either; those track edits made
through the tool's own file editing, so whatever a shell
command moved or deleted is outside them.
_Anchor:_ an agent told to tidy up branch history ran a hard
reset and destroyed a day of work; nothing had been tagged, and
the tool's rewind had never seen the files.

### Back up and confirm before destructive work on live data

A `DROP`, a `TRUNCATE`, an unbounded `DELETE` or `UPDATE`, a
migration, or a wipe of a bucket, document collection, or search
index — a "reset the data and start clean" counts — against
anything but a local throwaway store is a two-step action: confirm
a current backup exists, then get an explicit yes that names the
target and what will be lost. Automatic backups are the cheap
half; the confirmation is the half that catches the wrong
connection string. Quote the blast radius in the store's own units
— table rows, bucket objects, collection documents — not as a
pasted command.
_Anchor:_ an agent ran a destructive operation against a
production database it believed was a test instance and emptied
it in seconds; there was no staging tier and no recent backup.

### A conditional must not be a shell function's last command under errexit

Under `set -euo pipefail`, a trailing `[[ ... ]] && cmd` makes the
function return 1 on the false path, and a failed command substitution
in a bare assignment aborts the whole script. End helpers with an
explicit if/fi so the negative path returns 0.
_Anchor:_ a sid-guard tightening made a session-start hook abort on
routine stray files; context loading silently stopped, and only
independent verification caught it because the suite passed.

### Assert the positive outcome, not the absence of the symptom

A test that only checks an error string is absent also passes when the
code crashes to empty output. Pair every negative assertion with one
that the wanted artifact was produced (marker emitted, exit 0, file
present).
_Anchor:_ a hook-killing crash sailed through a 1400-assertion suite
because the new regression test asserted only that a warning string
was absent; the crash made it absent too.

### In cross-platform fallback chains, the noisy-failure variant goes last

Order `A || B` so the variant that misbehaves on the wrong platform
never runs first. Some commands "fail" by succeeding partially with
garbage on stdout (GNU `stat -f` prints filesystem stats), which
poisons the captured value even though the fallback also runs.
_Anchor:_ a BSD-first stat chain made a required Linux CI job a coin
flip; it passed for weeks by luck, then failed an unrelated PR.

---

## Process

### One canonical decisions file; archive everything else

All locked decisions live in a single file (`CURRENT.md`,
`DECISIONS.md`, or similar). Old files move to `_archive/`. New
decisions update the canonical file, not new files. AI agents take
shortcuts when reading everything isn't tractable, so the canonical
file must be loadable into context.
_Anchor:_ project accumulated dozens of decision documents and
memory entries; agent began making decisions inconsistent with
locked ones because it couldn't read everything in a single pass.

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

### Commit each fix immediately; don't batch

Each logical fix is its own commit. Group only when tightly coupled
(a fix plus the test that prevents its regression). AI tools love
to batch fixes into larger diffs because each individual change
feels small and the cumulative work feels productive.
_Anchor:_ mixed commits become unrevertable when one fix turns out
to be wrong; pre-commit failures force re-stage cycles when many
unrelated changes are batched together.

### Commit atomically without waiting for per-commit approval

This overrides the generic "never commit unless explicitly asked"
default some tools ship with. On a feature branch or worktree, once
a logical unit of work passes its own gate (tests, lint, the checks
this repo already runs), commit it immediately and move on. Do not
pause mid-task to ask permission for each individual commit; that
default exists to stop unwanted proactive commits, not to add a
confirmation step to work the user already asked for. Pushing,
merging into a protected branch, and force-pushing still need their
own explicit approval every time; committing locally on a branch
already in scope does not.
_Anchor:_ mid-session, an agent kept asking before each commit on a
branch the user had already scoped and approved the work for; the
user had to explicitly say "always do atomic commits, do not wait
for me" to stop the interruptions.

### Locked decisions are revisitable on new evidence

Surfacing new evidence and proposing a revisit IS appropriate.
Re-litigating with the SAME evidence the lock was made with is not.
Classify new evidence: was it available at lock time? load-bearing
on the original decision? strategy update or full unlock?
_Anchor:_ a format decision was locked before per-unit size was
measured; the measurement constituted real challenge evidence, not
noise, and warranted explicit revisit rather than silent override.

### Write down why, not just what

Code comments and decision documents should explain why a choice
was made, not just what the code does. AI tools regenerate "what"
on demand from any "why." Without "why," future sessions can't
distinguish load-bearing decisions from incidental ones.
_Anchor:_ a refactor session removed a workaround whose reason had
never been written down; the original bug returned weeks later
and required rediscovery from scratch.

### Version bumps travel only in release commits

A feature PR that bumps the version strands the mainline on an
unreleased number the moment it merges, and consumers that track the
branch install untagged builds. Bump, changelog heading, tag, and
release move together in a dedicated release change: a staged edit
to a `version` field in a manifest (`package.json`, `pyproject.toml`,
`Cargo.toml`, a packaged formula) belongs only in a commit whose
subject is `chore(release): vX.Y.Z`.
_Anchor:_ a feature merge bumped to 0.18.0 while the latest tag was
v0.17.0; marketplace installs tracked main and picked up an unreleased
version, and an earlier install matched no released version at all.

### A check that can pass by luck is failing

When a test turns out to be nondeterministic, stop and make it
deterministic before merging anything through it; rerunning until
green is papering over. Treat the first unexplained flake as a defect
with a root cause, not weather.
_Anchor:_ a flaky assertion passed one PR's required CI job and failed
the next identical run minutes later; the two-line fix existed only
because the failure was investigated instead of rerun.

### Track work in at most two places

The issue tracker is the single home for open work items (tasks, bugs,
follow-ups); memory and docs hold pointers to it, never a second live
list of what's outstanding. This is distinct from the canonical-
decisions-file rule above (that one governs locked decisions, not open
work): prune finished items when they close, and resurface every open
item at session start, however old.
_Anchor:_ a project kept work state in three places; finished issues
were never pruned, open issues were never resurfaced, and a session
scratchpad list silently became a third divergent copy.

---

## Collaboration

### Agent reports measurements; user calls "fixed" / "done"

Concrete numbers (test counts, throughput, byte sizes, gate pass
rates, latency) come from the agent. Verdicts ("fixed", "done",
"verified", "working") come from the user. AI tools tend to declare
victory based on surface pattern matching rather than verified
behavior; reserving the verdict for the human prevents premature
"fixed" claims.

### Close every handoff with a plain-language summary

The artifact that makes the rule above usable. Before handing back a
commit, a PR, or the session itself, state in plain language what
changed and why, anything destructive or hard to reverse, every check
you turned down by name, and what the user should verify before calling
it done. That summary is the decision surface for anyone who does not
read diffs; it feeds the verdict, it never delivers it.
_Anchor:_ every enforced output of an AI-assisted change (the diff, the
failing check, the CI log) assumes a reader who reads code; where the
accountable human did not, a downgraded guardrail shipped with nothing
but the diff recording it.

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
_Anchor:_ a session noticed a pre-existing lint finding, labeled it
"out of scope," and moved on; with nothing tracking it, it was
forgotten until it resurfaced later as a failure.

### Record every skip, deferral, and flag before moving on

The complement to the rule above: that one covers what you NOTICE,
this one covers what you DECIDE. A skipped test, a check that
no-op'd because its tool was absent, a question left unanswered, a
workaround taken "for now", scope deliberately not taken — each
lands somewhere durable AT THE MOMENT it happens: an issue, a
tracked fix-list, a TODO with an owner. Record why it was skipped
and what would unblock it; a bare title is not actionable later.
Chat is not durable — the transcript scrolls away and the next
session starts from the code, not from what was said. A PR
description is only durable if the item also exists outside it.
_Anchor:_ a harness printed "skipped (tool not installed)" on every
runner for months; the check it guarded had never once executed,
and nothing recorded that it wasn't running.

### Surface uncertainty rather than guessing

When the agent doesn't have enough context to make a decision
confidently, the right move is to ask, not to guess and proceed.
Confident-sounding wrong answers are more expensive than honest
"I'm not sure, here's what I'd need to know" responses.

### Nudge a stalled delegate; a promise to wait is not a report

A delegated agent that ends its turn saying it will wait for a
background run has stalled: the notification it is waiting for is not
coming. Prompt-level "run everything in the foreground" instructions
reduce but do not prevent this. Send the agent one direct message to
run the remaining work in the foreground and deliver its full report;
the nudge reliably recovers both the agent and the work.
_Anchor:_ two implementation agents in one session each launched their
final test suite in the background and stopped to "wait" despite
explicit foreground-only instructions; both delivered complete results
after a one-line nudge.

### One writer per repo at a time; check before merging

Before merging or releasing, re-fetch and check for other active
sessions' open PRs and recent mainline movement. A second writer
merging mid-orchestration invalidates in-flight audits and can leave
provenance untraceable after the fact.
_Anchor:_ a PR was merged by a concurrent session no one could later
identify, minutes after another session's audit snapshot; the version
drifted and the audit had to be redone against a moved main.

### Destructive filesystem work needs the one-writer check too

Deleting, moving, or repointing a path another session may be using
(a checkout, a worktree, a symlink target) is a merge-grade write,
and the merge-level check (open PRs, mainline movement) sees none of
it. Check the signals you can actually read: issues or commits
freshly filed from that path, recent file mtimes, open handles or
processes. Any positive signal means stop and ask; true idleness is
unprovable, so with no signals the bar is an explicit go-ahead naming
the path, and prefer a rename over an immediate hard delete so a
late writer fails loudly instead of by luck.
_Anchor:_ a session deleted a duplicate repo checkout minutes after a
concurrent session had filed an issue from inside that directory; the
PR-and-mainline check had been run and caught nothing, and only luck
decided whether the other session's next write hit a deleted path.

### End every session with a rules retrospective

Before handoff, walk the session's incidents against this file's
add-criteria and propose additions through this repo's issue flow; a
lesson that lives only in a transcript or a repo-local issue is lost
to every other project.
_Anchor:_ an orchestration session filed its lessons as a repo-local
issue only; the owner had to ask explicitly before the generalizable
rules were proposed to the global file every session actually loads.

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
