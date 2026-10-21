# Operational rules

Where a project's `AGENTS.md` says something different, the project's rule wins; these rules apply
only where the project is silent.

Judgment and collaboration rules for working with AI agents. Rules about the code live in
[`coding-rules.md`](./coding-rules.md), repo mechanics and red lines in [`AGENTS.md`](./AGENTS.md);
this file never restates them.

## Engineering

### Fix the file, not the guardrail

`AGENTS.md` > "Checks" says when a suppression is allowed and that it gets named. If the check
itself is wrong, fix the check and add a test. When a test is deleted, name it, why it no longer
applies, and where its coverage went.
_Anchor:_ an exemption, unlike a fix, never expires, so suppressions accrete until the scanner no
longer scans.

### Diagnose before you silence

Before quieting a failing check, establish what it is actually reporting: a suppression added for
a symptom can delete the only evidence of a live problem. Suppressions that never go red still
count: a dependency-update ignore rule, a CI path-filter exclusion, a commit prefix renamed to
satisfy a hook, a slow verification step skipped. Where a constraint must stay, prefer an assertion
that fails over a comment that explains.
_Anchor:_ an ignore rule silencing a failed dependency upgrade hid the only signal that the runtime
was past end of life.

### Choose the strongest approach at the fork

Decide between the robust approach and the quick one before writing the fix; once the fast path is
built, sunk cost decides. When speed is the only reason to prefer a path, slow down.

### Gate the merge result, not the branch

With several branches open against one base, per-file gates (size, lint, coverage) that pass on
each branch can fail on the merge. Before syncing, build the merge tree
(`git merge-tree --write-tree <base> <branch>`) and run the cheap gates on it; fix a breach in the
merge commit.
_Anchor:_ two branches each under a file's size cap merged into a file over it.

## Process

### One durable home per kind of state

Open work lives in one place and locked decisions in another; everything else points at them. Prune
items when they close, resurface every open one at session start, and keep what an agent must obey
small enough to read in one pass.

### Pre-flight, then smoke at the smallest full-path scale

Before any job longer than five minutes, check each external dependency in seconds: database
reachable, schema migrated, auth valid, disk space, output writable. After a non-trivial change,
run one unit first, through every component that fails at scale; scale only after it passes.
_Anchor:_ a 4-unit smoke caught worker contention; a 1-unit smoke proved the fix.

### Write down why, not just what

Comments and decision records explain why a choice was made; the what can be regenerated, the why
cannot.
_Anchor:_ a refactor removed a workaround whose reason was never written down; the bug returned.

### A check that can pass by luck is failing

When a test proves nondeterministic, make it deterministic before merging anything through it;
rerunning until green is papering over. Treat the first unexplained flake as a defect with a cause.

### A recorded workaround is an unfiled bug

A documented workaround for a recurring failure ("rename the cache dir", "ignore the 5 known
flakes") lowers the baseline for every later session. Find the defect at the first workaround; if
it cannot be fixed now, file it with the cause named and keep the check red.
_Anchor:_ a suite carried "known flakes" as its baseline for a week while the product bug behind
them shipped.

## Collaboration

### Agent reports measurements; user calls "done"

Numbers (test counts, sizes, latency, pass rates) come from the agent. Verdicts ("fixed", "done",
"verified", "working") come from the user. The handoff carrying them is `AGENTS.md` >
"Plain-language change summary".

### An agent's report is final

Never end a turn or hand back while a job you started is still running: run the last verification
in the foreground, stop the job, or report it unfinished with its id and how to check it. A promise
to wait is not a report, and an agent that made one is still a live writer: send no one else into
its tree.
_Anchor:_ an agent handed back mid-run, woke when its job finished, and rewrote a tree a second
agent was already using.

### Inherited state is a hypothesis

A claim you did not measure this session (a handoff, PR text, a memory note, a local clone) about CI,
branch position, conflicts, open decisions, or versions is re-measured from the system of record,
naming the command, before it drives an action. CI fails only at job level with steps that ran;
count branch position both ways; test conflicts with a trial merge; ask a repository's host, not a
clone.
_Anchor:_ a handoff called a PR red whose CI job had been cancelled before a single step ran.

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
path. Prefer a rename to a hard delete.
