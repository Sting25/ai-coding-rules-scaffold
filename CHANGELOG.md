# Changelog

All notable changes to this project are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [SemVer](https://semver.org/).

## [Unreleased]

## [v0.3.0] — 2026-04-28

### Added
- Scaffold self-tests (`tests/run.sh`) verifying hook behaviour on six fixture
  cases, run on Linux + macOS via matrix CI.
- `permissions: contents: read` on all GitHub workflows.
- `forbidden-patterns/README.md` — developer reference for the pattern format.

### Changed
- Function-size limit raised from 60 to 80 (`ruff max-statements`,
  `eslint max-lines-per-function`); README and `coding-rules.md` aligned.
- Pre-commit hook checks extracted into `.githooks/lib/check-{size,patterns,
  filenames,secrets}`. The CI workflow invokes the same scripts, so the hook
  and CI cannot drift in behaviour.
- Forbidden-patterns separator switched from `|` to TAB. Patterns can now
  contain literal `|` for ERE alternation (e.g. `(TODO|FIXME|XXX)`). v0.3
  roadmap item 1.
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
