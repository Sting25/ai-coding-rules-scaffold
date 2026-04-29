# Changelog

All notable changes to this project are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [SemVer](https://semver.org/).

## [Unreleased]

### Security / hardening (audit pass)
- **Unicode filename bypass closed.** `git diff --cached --name-only`
  honoured `core.quotepath=on` (the default), C-quoting non-ASCII names
  like `"caf\303\251.py"`. The downstream `[ -f "$file" ]` check then
  failed and the file was silently skipped — every scanner bypassed.
  Hook + `lint.yml` now run with `-c core.quotepath=off`.
- **Stash-failure no longer silently downgrades.** If
  `git stash --keep-index` fails (submodule conflicts, lock contention),
  the hook now aborts with a clear error rather than falling through to
  scan the dirty working tree (which would re-open the bypass v0.3.0
  closed).
- **Invalid forbidden-pattern handling.** A malformed ERE in
  `.forbidden-patterns/*.txt` previously poisoned the combined regex
  and silently dropped every file in the scan. Patterns are now
  validated up-front; invalid ones are warned about and dropped, valid
  ones continue to scan.
- **`MAX_LINES` env var validated.** Non-numeric values used to cause a
  cryptic `[: integer expression expected` mid-scan; now exit 2 with a
  clear message before any file is read.

### Fixed
- `uninstall.sh` uses `git rev-parse --git-dir` (matching `install.sh`)
  so `core.hooksPath` is correctly unset in worktrees and submodules.
- Pre-commit header comment described the pattern format as
  `regex|description`; corrected to TAB-separated to match v0.3.0.
- `check-secrets` skip list extended to cover `.exe`, `.dll`, `.so`,
  `.dylib`, `.bin`, `.class`, `.pyc`, `.pyo`, `.o`, `.a`, `.parquet`,
  plus `go.sum` and named lockfiles (`Cargo.lock`, `Gemfile.lock`,
  `composer.lock`, `poetry.lock`, `yarn.lock`). Cuts false positives
  and slow scans.
- `[a-z]+://` URL-with-credentials pattern in `secrets.txt` widened to
  `[a-zA-Z]+://` so the regex reads correctly without depending on
  `grep -i`.
- Stale `[[:<:]]print` example in `forbidden-patterns/README.md`
  updated to the POSIX-portable `(^|[^A-Za-z_])print` form actually
  used elsewhere in the doc.

### Added
- **Per-line `scaffold-allow` marker.** Lines containing `scaffold-allow`
  (case-insensitive) are exempt from `check-patterns` and `check-secrets`
  — an inline `# noqa`-style escape valve for legitimate `print` calls,
  docs examples showing key prefixes, and synthetic test fixtures. Audit
  usage with `git grep -i scaffold-allow`. `check-filenames` and
  `check-size` ignore the marker (they're file-level rules).
- Pre-commit hook now runs `ruff` / `eslint` against staged files when
  their configs are present and the tool is on PATH. Cuts the
  edit→push→CI→fix loop; CI remains the authoritative backstop.
  Silently skipped when a tool isn't installed so the hook doesn't break
  on fresh checkouts.
- `actions/setup-python` + `pip install ruff` step in `tests.yml` so the
  new ruff-integration test case actually exercises lint at hook time.

### Changed
- `check-patterns` and `check-secrets` rewritten to combine all patterns
  into one ERE per scan and run a single `grep` per file as a fast-path
  filter. Per-pattern attribution only runs on files that already
  matched something. Cuts grep invocations from O(P×F) to F + matching×P
  — meaningful on the CI path where `git ls-files` feeds in thousands of
  files.

### Fixed
- "Clean Python file" test fixture (`tests/run.sh` case 6) gained the
  blank line between `import logging` and the rest, which ruff I001
  requires now that the hook lints.

## [v0.3.2] — 2026-05-02

### Added
- `operational-rules.md` — process, collaboration, and judgment rules
  extracted from real failure modes (pre-flight checks before long
  jobs, smoke at the smallest scale that exercises the full path,
  "agent reports measurements / user calls done", scope discipline,
  surfacing uncertainty rather than guessing). Sibling document to
  `coding-rules.md`; auto-installed by `install.sh` and referenced
  from `AGENTS.md.template`. Standalone use supported via a one-line
  `@operational-rules.md` directive in `CLAUDE.md` for users who
  don't want the rest of the scaffolding.

### Changed
- `AGENTS.md.template` gains an "Operational rules" section pointing
  at `operational-rules.md` alongside the existing "Coding rules"
  section.
- `README.md` "AI agent integration" section gains a "Use the rules
  without the rest of the scaffold" subsection — minimal recipe for
  adopting `operational-rules.md` / `coding-rules.md` standalone via
  `@`-import in `CLAUDE.md` (or the equivalent in Cursor / Aider /
  Cline configs). Aider and Cline config snippets updated to include
  `operational-rules.md`. New row in the "What lands in your project"
  table.

## [v0.3.1] — 2026-05-01

### Added
- `RECOMMENDATIONS.md` — entries for ideas the scaffold deliberately doesn't
  ship (agent-runtime hooks, `SPEC.md` templates, language-agnostic forbidden
  patterns) with explicit triggering conditions and a maintenance protocol so
  entries don't bit-rot. Closes the documented gap from the v0.3.0 audit cycle.

### Changed
- README `Why this exists` rewritten with concrete failure-mode mechanics
  (Monday/Wednesday inconsistency, agents-grow-files-they-can't-see, debug
  statements that look like logging, recurrent training-data muscle memory)
  rather than abstract failure-mode names. Origin context and audience now
  explicit.
- README install command now pins `--branch v0.3.1` by default; tracking
  `main` is shown as the alternative. Matches the scaffold's reproducibility
  preaching.
- `AGENTS.md.template` Project section gains a 30-line budget note,
  nested-`CLAUDE.md` guidance, and a "Module pattern" line. Git-discipline
  section gains a `git worktree` bullet so parallel agent sessions don't
  overwrite each other.

### Fixed
- `install.sh` post-install smoke test now distinguishes a bad ruff config
  (exit ≥ 2) from successful runs (exit 0 or 1). The previous
  `--exit-zero` form silently passed even when ruff hit a config error.

## [v0.3.0] — 2026-04-28

### Added
- Scaffold self-tests (`tests/run.sh`) — 10 fixture cases verifying hook
  behaviour, matrix-run on `ubuntu-latest` and `macos-latest` via CI.
- `permissions: contents: read` on all GitHub workflows.
- `forbidden-patterns/README.md` — developer reference for the pattern
  format.
- `forbidden-patterns/shell.txt` — dangerous shell patterns
  (`curl|bash`, `rm -rf /`, `chmod 0?777`) for `*.sh` and `*.bash`. v0.3
  roadmap item 2, unblocked by the TAB-separator change.
- `CHANGELOG.md` (this file).

### Changed
- Function-size limit raised from 60 to 80 (`ruff max-statements`,
  `eslint max-lines-per-function`); README and `coding-rules.md` aligned.
- Pre-commit hook checks extracted into `.githooks/lib/check-{size,patterns,
  filenames,secrets}`. The CI workflow invokes the same scripts, so the hook
  and CI cannot drift in behaviour.
- Forbidden-patterns separator switched from `|` to TAB. Patterns can now
  contain literal `|` for ERE alternation (e.g. `(TODO|FIXME|XXX)`). v0.3
  roadmap item 1.
- Six per-keyword hardcoded-credential patterns (`password`, `passwd`,
  `token`, `api_key`, `secret_key`, `access_token`) collapsed into one
  alternation pattern in `secrets.txt`, enabled by the new separator.
- Pattern files use POSIX-portable word boundaries `(^|[^A-Za-z_])` and
  `($|[^A-Za-z0-9_])` instead of GNU-only `\b` or BSD-only `[[:<:]]`.
  Verbose, but works on every `grep -E` that supports ERE alternation
  (GNU, BSD, busybox). Whitespace uses `[[:space:]]`, also POSIX.
- GitHub Actions pinned to commit SHAs (`actions/checkout` v4.3.0,
  `actions/setup-python` v5.6.0, `actions/setup-node` v4.4.0). v0.3 roadmap
  item 3.
- `coding-rules.md` enforcement table replaced with a pointer to `README.md`
  — single source of truth for the rule matrix.

### Fixed
- Test-fixture AKIA string in `tests/run.sh` split across adjacent quoted
  segments so the secrets scan does not false-positive on its own data.
- File-size check now uses `grep -c ''` instead of `wc -l`, correctly
  counting the last line of a file without a trailing newline (which
  `wc -l` silently misses).
- `install.sh` uses `git rev-parse --git-dir` instead of `[ -d .git ]` to
  detect a git repo, so it works in worktrees (where `.git` is a file)
  and submodules.
- Pre-commit hook now `git stash --keep-index`s unstaged changes before
  running checks, so each check sees the staged content rather than the
  working tree. Closes the bypass where staging bad code and then editing
  the working tree clean would let the dirty index commit through. Skipped
  during merge / rebase, where stash is unsafe.

## [v0.2.0] — 2026-04-23

### Added
- Secret / credential pattern scanning across all tracked text files
  (AWS, Google, GitHub, Slack, OpenAI/Anthropic prefixes; private keys;
  URL-embedded credentials; hardcoded password/token assignments).
- Python debug-leak patterns (`breakpoint`, `pdb.set_trace`, `ipdb.set_trace`).
- Filename block list (`.env`, `*.pem`, SSH private keys).
- `shellcheck` CI on the scaffold's own scripts.
- Cleaned up `ruff` ignore list.

## [v0.1.0]

### Added
- Initial release: agent-agnostic scaffold (`AGENTS.md` + `CLAUDE.md` pointer).
- Pre-commit hook: file-size cap and Python/JS forbidden patterns.
- CI mirror (`.github/workflows/lint.yml.template`).
- `install.sh` and `uninstall.sh`.
