# Operational rules

Judgment and collaboration rules for working with AI agents. Rules about the code live in
[`coding-rules.md`](./coding-rules.md); repo mechanics and red lines (checks, git, destructive
actions, secrets, the change summary) live in [`AGENTS.md`](./AGENTS.md). This file never restates
them.

## Engineering

### Fix the file, not the guardrail

`AGENTS.md` > "Checks" says when a suppression is allowed and that it gets named. If the check
itself is wrong, fix the check and add a test. When a test is deleted, name it, why it no longer
applies, and where its coverage went.
_Anchor:_ an exemption, unlike a fix, never expires, so suppressions accrete until the scanner no
longer scans.

### Choose the strongest approach at the fork

Decide between the robust approach and the quick one before writing the fix; once the fast path is
built, sunk cost decides. When speed is the only reason to prefer a path, slow down.

## Process

### One durable home per kind of state

Open work lives in one place and locked decisions in another; everything else points at them. Prune
items when they close, resurface every open one at session start, and keep what an agent must obey
small enough to read in one pass.

### Pre-flight catches beat mid-run discovery

Before any job longer than five minutes, check each external dependency in seconds: database
reachable, schema migrated, auth valid, disk space, output writable.

### Smoke at the smallest scale that exercises the full path

After a non-trivial change, run one unit first, through every component that fails at scale; scale
only after it passes.
_Anchor:_ a 4-unit smoke caught worker contention; a 1-unit smoke proved the fix.

### Locked decisions are revisitable on new evidence

Propose a revisit when evidence appears that was not available at lock time and bears on the
decision; re-litigating with the same evidence is not a revisit.

### Write down why, not just what

Comments and decision records explain why a choice was made; the what can be regenerated, the why
cannot.
_Anchor:_ a refactor removed a workaround whose reason was never written down; the bug returned.

### Version bumps travel only in release commits

For a published package, the version bump, changelog heading, tag, and release move together in a
dedicated release change; a feature change never bumps the version.

### A check that can pass by luck is failing

When a test proves nondeterministic, make it deterministic before merging anything through it;
rerunning until green is papering over. Treat the first unexplained flake as a defect with a cause.

## Collaboration

### Agent reports measurements; user calls "done"

Numbers (test counts, sizes, latency, pass rates) come from the agent. Verdicts ("fixed", "done",
"verified", "working") come from the user. The handoff carrying them is `AGENTS.md` >
"Plain-language change summary".

### Plans default to PROPOSED; mark every assumption

Mark each value you picked yourself PROPOSED, with a one-line "alternative would be Y because Z".
The user redirects what is wrong and accepts the rest.

### Pause signals stop work

"Hold on", "wait", "hmm", or "actually" means the user saw something you missed. Finish the
in-flight edit, summarize the current state, and ask what prompted the pause.

### Ask before expanding scope

A request to fix A is not permission to refactor B. Raise the expansion as a separate question.

### Capture what you notice and what you defer

Out of scope means do not expand the change, not pretend you did not see it. A pre-existing bug,
drift, or stale doc you noticed, and every skipped test, no-op check, open question, temporary
workaround, or scope not taken, goes somewhere durable when it happens (an issue, a tracked list, a
TODO with an owner) with why and what would unblock it; the user decides fix now or later. Chat
is not durable; a PR description counts only if the item also exists elsewhere.
_Anchor:_ a check reported "skipped" on every run for months and never once executed.

### One writer per repo at a time

Before merging or releasing, re-fetch and check for other sessions' open PRs and recent mainline
movement. Deleting, moving, or repointing a path another session may use (a checkout, a worktree,
a symlink target) is a merge-grade write: look for live signals (fresh commits or issues from it,
recent file times, open processes) and stop and ask on any; with none, get a go-ahead naming the
path. Prefer a rename to a hard delete, so a late writer fails loudly.
