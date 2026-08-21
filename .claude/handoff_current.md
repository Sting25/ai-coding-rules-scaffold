# ai-coding-rules-scaffold — session handoff (auto-generated)

**Generated:** 2026-08-21 11:17 UTC

<!-- HANDOFF_ROOT: /Users/brain/ai-coding-rules-scaffold in_git=1 -->

Auto-written by `~/.claude/bin/write_handoff.sh` (called from the
`/handoff` skill + the `SessionEnd` hook in `~/.claude/settings.json`).
Auto-loaded into the next session by the `SessionStart` hook in the
same settings file. Lives at `<root>/.claude/handoff_current.md`, where
`<root>` is resolved from the Claude Code project dir (falling back to
the hook payload's cwd, then the process cwd) and then anchored on that
dir's git toplevel — the same resolution the loader uses, recorded in the
`HANDOFF_ROOT` comment above. The previous handoff is rotated to
`.claude/handoff_history/` before
overwrite (last 5 retained; override via `HANDOFF_HISTORY_KEEP`).
Run `/handoff-more` in a fresh session to pull older handoffs into context.

---

## Repo: ai-coding-rules-scaffold

**HEAD:** `adbc959` — Merge pull request #77 from Sting25/feat/shell-install-mode-65

**Branch:** `main` (main...origin/main)

### Recent commits

```
adbc959 Merge pull request #77 from Sting25/feat/shell-install-mode-65
8732af8 fix: split forbidden literals so the scaffold's own guardrails pass
b423e45 feat(install): add shell-only install mode (--shell) with auto-detect
f12b73a Merge pull request #75 from Sting25/feat/untrack-vs-delete-65
00f0176 feat(hook): warn on untracking pattern config, fail only on real deletion
80fa1e1 Merge pull request #74 from Sting25/fix/secrets-case-sensitivity-67
58b03e8 test(secrets): guard against a (?-i) marker leak at load time
c0250c6 fix(agent-precheck): strip the (?-i) marker too (fail-open on GNU grep)
9107b3c fix(secrets): match token-shaped rules case-sensitively (#67)
28d555d Merge pull request #68 from Sting25/chore/setup-python-v7
```

### Working tree

```
 M .gitignore
?? .claude/
```

## Verify state matches reality

```bash
git -C /Users/brain/ai-coding-rules-scaffold status && git -C /Users/brain/ai-coding-rules-scaffold log --oneline -5
```

<!-- HANDOFF_BIND_BEGIN -->
## Rules (fences — carried into the next session)

- Never merge a PR in this repo until CI is green on **both** `test (ubuntu-latest)` and `test (macos-latest)`, plus `guardrails` and `shellcheck`. There is no branch protection; nothing enforces this but you. Two separate failures this session were visible on exactly one runner.
- Never treat a local test pass as authoritative for a change to a regex, a grep flag, or pattern parsing. This machine's `grep` is ugrep and is laxer than both GNU and BSD grep. Push and read CI instead.
- Before running any self-lint / guardrails simulation, `git add` the files under test first. The scanners read the **index** blob (`git show ":0:<path>"`), so an unstaged run silently scans the old committed content and reports a false green.
- Do not re-propose RPM/Copr packaging (issue #57) without evidence of real user demand. That was decided 2026-07-19 and the draft is preserved in the issue.
- Do not commit the working tree's `.gitignore` modification as part of unrelated project work. It is prior-session handoff-tooling bootstrap; commit it deliberately on its own or leave it.
<!-- HANDOFF_BIND_END -->

---

## Notes from this session

**Clean boundary — nothing in flight.** Everything this session is merged
to `main` and pushed. The next session starts a NEW batch of work that was
already chosen by the user (see "Pick up here").

### Start here

```bash
cd /Users/brain/ai-coding-rules-scaffold && git status && git log --oneline -3
gh issue list --state open && gh pr list --state open
./tests/run.sh 2>&1 | tail -2     # expect: Result: 239 passed, 0 failed
```

State claims as checks, not verdicts:
- This session's work is fully landed **iff** `gh issue list` shows #65, #66,
  #67 absent (closed) and `gh pr list` shows #63, #64, #68, #74, #75, #77 absent.
- The tree is healthy **iff** `./tests/run.sh` ends `239 passed, 0 failed` and
  `shellcheck -S info` over the CI file list exits 0.

### Pick up here — the user already approved all four, in this order

1. **Issue #72 — `install.sh` silently destroys project-local pre-commit /
   `lint.yml` wiring, with no backup unless `--force`.** Highest severity: it
   destroys user work, and the whole `cp_safe` / `_backup` policy exists to
   prevent exactly that, so this reads as a hole in a load-bearing guarantee.
   Read the policy comment block in `install.sh` (~line 87, "file ownership &
   the install/upgrade model") and `install-lib.sh` before proposing a fix.
2. **Issue #71 — `coverage.yml`: `|| true` lets a PR with failing tests pass
   the gate.** A guardrail that silently passes is the exact failure class this
   repo exists to prevent. Likely small; verify by mutation (make a test fail,
   confirm the gate currently goes green, then confirm it goes red after).
3. **Issues #73 and #76 — dogfooding failures.** #73: the shipped
   `coding-rules.md` / `operational-rules.md` fail the prettier config the
   scaffold itself ships. #76: the prescribed whole-tree commands
   (`npx eslint .`, `pytest`) break on gitignored content the installed configs
   do not exclude. Both are "the scaffold does not pass its own prescriptions".
   Note #73 touches `operational-rules.md`, which is **symlinked** into the
   global `~/.claude/` copy — editing it changes rules loaded in every session
   everywhere, so decide deliberately.
4. **PR #70 — Dependabot `setup-node` 6.5.0 → 7.0.0.** It will be red on the
   pin-drift guard. Same hand-finish as #63/#68: bump the pin in the real
   `.yml` *and* every `*.yml.template`, then verify locally with the drift
   snippet in `test.yml` before pushing.

### What shipped this session

Cleared the whole prior backlog. Merged #64 (checkout/setup-node SHA refresh),
#68 (`setup-python` v6.3.0 → v7.0.0 — the bump #64 missed, verified safe
because all three call sites pass only `python-version: "3.12"`), #74 (issue
#67), #75 + #77 (issue #65, both parts). Closed #63 (superseded) and #66
(declined — dash normalization, won't-fix; rationale posted on the issue).
Suite **227 → 239**, every new case mutation-proven in both directions.

Substance worth knowing:
- **#67** — `check-secrets` applied `grep -i` to every rule; `ACCA` is all hex,
  so case-folded it matched inside SHA-256 digests and failed any repo with a
  lockfile. Introduced a `(?-i)` marker the runner strips into a case-sensitive
  grep. 34 token rules carry it, 3 keyword/URL rules deliberately do not.
- **#65 part 1** — untracking a pattern file (`git rm --cached`, file still on
  disk) now warns instead of hard-failing. The issue flagged a MUST-CHECK that
  this could reopen a hole closed by `5ced87a`/`3ef4ad9`; **verified it does
  not** — every check reads pattern config from the working tree, and
  `git show ":0:"` appears in those scripts only for scanned content.
- **#65 part 2** — `install.sh --shell` plus a manifest-less auto-detect
  fallback. Went beyond the issue with a second probe (working tree, not just
  `git ls-files`) so a fresh uncommitted repo works, and added a precedence
  test so a manifest always beats the fallback.

### Traps that produced FALSE GREENS — do not repeat

Both are now fences above; the mechanism is here.

- **Index vs working tree.** My first self-lint simulation passed because the
  scanners read `git show ":0:<path>"` and my edits were unstaged — it scanned
  the old clean blob. Stage first.
- **ugrep vs GNU vs BSD grep.** The `(?-i)` marker leaked into `agent-precheck`
  (which reads `secrets.txt` **independently** of `check-secrets`). GNU grep
  rejects it as an invalid ERE — and both scripts **DROP** invalid patterns
  rather than failing — so on Linux all 34 marked rules silently disarmed, a
  fail-open. Green locally and on macOS, red only on ubuntu.
- **Generalize the second one:** any script here that skips a pattern it cannot
  compile converts a syntax mistake into a silent fail-open. When touching
  pattern parsing, check every consumer of the file, not just the obvious one.

### Recurring, reconfirmed

Dependabot grouped action bumps **always** go red in this repo — it bumps only
the real `.yml` and never the `*.yml.template` files, tripping the pin-drift
guard. Expect to hand-finish every one (#70 is the next). Explained publicly on
#63 so the record is not just Dependabot's vague auto-close note.

### Dropped from the previous handoff (graduated or stale)

- "Wait for CI on both runners" and "the 500-line cap is real" → promoted to
  fences / already in memory. Followed both this session (`cases/14` is a new
  file precisely because `cases/09` is near the cap).
- v0.11.0 release details, the handoff-tool SSH→HTTPS switch, and the
  handoff hook-presence enhancement idea → settled or already surfaced to the
  user; not carried forward.
- Still open and uncarried elsewhere: `prettier`/`phpcs` pre-commit linter
  blocks remain lightly covered (noted in `bf69f0c`). Partially overlaps #73.
<!-- HANDOFF_SKEL_HMAC: 0a4dd5bbe330f9750b03c92d0d6791697d73226c125e5191fc91e6ecb6d58b64 -->
<!-- HANDOFF_HMAC: edadef27e8410a8e9e6d9b442131138af50b4579ca19e6e01ff6b43d95ad8fb8 -->
