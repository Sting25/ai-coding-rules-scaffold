# Changelog

All notable changes to this project are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [SemVer](https://semver.org/).

## [Unreleased]

### Added
- **2025 provider-token shapes + JWT in `secrets.txt` (default-on).** Prefix-
  specific, low-FP additions the offline gate was missing: OpenAI
  service-account/admin (`sk-svcacct-`/`sk-admin-`), Hugging Face (`hf_`), GitLab
  (`glpat-`), npm (`npm_`), PyPI upload (`pypi-…`), Stripe live/restricted
  (`sk_live_`/`rk_live_`), Slack webhook URLs, DigitalOcean (`dop_v1_`),
  Databricks (`dapi…`, boundary-anchored), Perplexity (`pplx-`), plus a
  structural **JWT** pattern (two `eyJ…` segments) for leaked long-lived service
  keys. +8 fixtures incl. a `scaffold-allow` negative for an expired demo JWT.
- **TLS-verification-disable deny-patterns (`frontend.txt`, default-on).**
  `NODE_TLS_REJECT_UNAUTHORIZED` and `rejectUnauthorized: false` — the canonical
  AI-agent shortcut when a request fails against a self-signed cert, which
  silently disables MITM protection for every subsequent connection. It's an
  option *value*, not syntax, so no `eslint` rule catches it. +3 fixtures
  (incl. a negative proving `rejectUnauthorized: true` passes).
- **`switch-exhaustiveness-check` (default-on, type-aware).** The one widely-
  recommended typed `eslint` rule no preset (incl. `strictTypeChecked`) enables.
  Fails the build when a `switch` over a discriminated union / enum misses a
  member — the classic bug where an agent adds a variant and updates some switch
  sites but not all, while `tsc` stays silent. `considerDefaultExhaustiveForUnions`
  treats an existing `default` as exhaustive, suppressing the main false-positive.
- **`eslint.config.js` opt-in blocks refreshed/added (all commented, inert).**
  The React-hooks block now uses the `eslint-plugin-react-hooks` **v6** flat
  presets (`flat.recommended`, with `recommended-latest` documented as the
  experimental React-Compiler upgrade) instead of the stale v5 hand-wired snippet.
  New commented `eslint-plugin-jsx-a11y` block (a11y issues AI-generated JSX
  ships) and an erasable-syntax block banning `enum` / parameter properties for
  teams running `.ts` via Node type-stripping.
- **More `ruff` rule groups, turning advice into enforcement.** `ASYNC`
  (flake8-async) fails the build on a blocking HTTP/file/subprocess call inside
  an `async def` — backing `coding-rules.md` rule 6 on the Python side (its TS
  twin `no-floating-promises` was already enforced). `FAST` (FastAPI) catches
  non-`Annotated` dependencies and unused path params, no-op on non-FastAPI code,
  backing rule 4. `G`/`LOG` (flake8-logging) fail on f-string/`%`/`.format()`
  inside log calls, backing rules 10-11; the idiomatic `logger.info("event",
  key=val)` form is not flagged. A **curated** flake8-bandit `S` subset
  (`S301/307/113/324/602/605/701/105/106`) adds AST-level security checks the
  regex secret-scanner can't see — deliberately NOT the whole `S` category
  (`S603/607/404/608/310` are FP-noisy on subprocess/SQL/urllib). `S311` is
  ignored; tests exempt `S101/105/106`.
- **Deprecated `datetime.utcnow()` deny-pattern (`backend.txt`).** Caught by the
  always-on regex layer (no `ruff` dependency); the AST `DTZ` group is
  deliberately not enabled — flagging every naive `datetime` is timezone *policy*
  with a high false-positive rate, and the deprecated idiom is fully covered by
  the one regex. A commented opt-in 12-factor `localhost`-URL line is added too
  (off by default — Python test clients legitimately target localhost).
- **Per-project rule overrides (`.scaffold.toml`).** A first-class, committed,
  auditable config layer the `check-*` scripts consume via a new pure-bash/awk
  reader (`lib/scaffold-config`, no python/jq dependency). A team can: raise the
  size cap globally or per glob (`[size]`), disable a forbidden-pattern or
  hygiene rule entirely, or downgrade any of them `error → warn` (still emitted
  as a CI `::warning::`, never silent). Rules are keyed
  `"<patternfile-stem>/<description>"`, plus `conflict-marker` / `case-collision`
  / `size`. Modifying a pattern's regex stays an edit to the `.forbidden-patterns`
  file you own (no duplicated regexes). A malformed config **fails safe** —
  rules stay fully enforced. **Security boundary:** `check-secrets` and
  `check-filenames` ignore `.scaffold.toml` by design, so secret/credential-file
  blocking cannot be disabled per-project. `lib/scaffold-audit` lists every
  active override and the CI guardrails job echoes it into the build log;
  `install.sh` ships an empty, fully-commented `.scaffold.toml`.
- **TypeScript enforcement, broadened (P0).** The shipped `eslint.config.js`
  now extends typescript-eslint's **`strictTypeChecked`** tier with
  `projectService` auto-discovery, so type-aware rules actually fire. Pinned
  `no-floating-promises` + `no-misused-promises` (the #1 silent-async bug),
  added import sorting / unused-import removal (`import-x/order`,
  `unused-imports`) as parity with `ruff`'s `I` / `F401`, and shipped an
  opt-in `react-hooks` block (rules-of-hooks + exhaustive-deps). Plain JS and
  test files get `disableTypeChecked` / loosened overrides. Header documents an
  escape hatch back to `strict` for projects without a `tsconfig.json`.
- **`tsc --noEmit` wired into both layers.** The pre-commit hook and the CI
  `lint.yml` frontend job now run a project-wide TypeScript type-check, guarded
  on `tsconfig.json` presence + TypeScript being installed (silently skipped
  otherwise, like the linters). Resolves the contradiction where
  `coding-rules.md` mandated a type-checker that ran nowhere.
- **Broader `frontend.txt` deny patterns.** Focused tests (`.only`, which
  silently skips the suite), `@ts-ignore` / `@ts-nocheck`,
  `dangerouslySetInnerHTML` (XSS), and hardcoded `localhost`/`127.0.0.1` URLs.
  New harness fixtures cover each, plus negatives proving `console.warn` and an
  ordinary `it(...)` test still pass. Opt-in commented patterns added for
  `eval`/`new Function` and an auth-bypass-flag guard.
- **New `check-hygiene` guard (hook + CI).** A fifth `lib/check-*` script that
  flags merge-conflict markers left in a staged blob (`<<<<<<<` / `|||||||` /
  `>>>>>>>`, but not a bare `=======` heading underline) and case-only filename
  collisions that corrupt case-insensitive checkouts (macOS/Windows). bash-3.2
  safe, fail-closed, same NUL-safe blob scan and `scaffold-allow` semantics as
  the other checks. +3 fixtures incl. a negative for reST underlines.
- **Agent-runtime guardrails — the deferred "layer three" (opt-in,
  `install.sh --claude`).** Ships a `.claude/settings.json` deny-list (the agent
  can't read `.env` / `*.pem` / `*.key` / `~/.ssh` / `~/.aws` or run a few
  catastrophic `rm -rf` commands) plus a `PreToolUse` hook
  (`.githooks/lib/agent-precheck`) that scans Write/Edit/Bash content against the
  same `.forbidden-patterns/secrets.txt` the commit-time scanner uses — blocking
  a hardcoded secret the moment the agent writes it. Needs `jq`; fails open
  without it (commit + CI remain the fail-closed backstops). +3 fixtures.
- **Conventional-Commits `commit-msg` hook (opt-in, `install.sh --commit-msg`).**
  Rejects subjects that don't match `type(scope): description`; merge / revert /
  fixup commits exempt. BSD-grep safe, zero dependencies. +3 fixtures.
- **gitleaks CI backstop template** (`.github/workflows/gitleaks.yml.template`,
  not auto-installed). SHA-pinned broad secret scanner as a separate CI job — the
  entropy-based complement to the narrow regex `check-secrets` gate.
- **Dependabot** (`.github/dependabot.yml` + consumer template, installed by
  default). Weekly grouped bumps of the SHA-pinned GitHub Actions so the pins
  don't rot.

- **Multi-language forbidden patterns (config-driven).** `check-patterns` now
  auto-discovers every `.forbidden-patterns/*.txt` and reads a
  `# scaffold-extensions:` header from each, so adding a language is just
  dropping a file — no script edit. Ships tuned, adversarially FP-reviewed
  pattern files for **PHP, Go, Rust, Java, Kotlin, Ruby** (plus `*.vue` + Vue
  `v-html` on the frontend set); FP-prone rules (Rust `.unwrap()`, Ruby `puts`,
  PHP `die/exit`, …) ship commented as opt-in. `install.sh` auto-installs a
  language's file when it detects the manifest (`go.mod`, `Cargo.toml`,
  `composer.json`, `pom.xml`/`build.gradle`, `Gemfile`), or all of them with
  `--all-langs`. backend/frontend/shell keep a built-in fallback mapping.
- **PHP linting.** `php -l` (syntax) + `phpcs` (when configured) wired into the
  pre-commit hook and a new `php` CI job (`setup-php` SHA-pinned). Ready-to-
  uncomment, SHA-pinned CI job stubs added for Go/Rust/Java/Kotlin/Ruby linters.
  +13 harness fixtures (a reject + a look-alike negative per language).

### Changed
- **CI uses a frozen-lockfile install.** The frontend job runs `npm ci` when a
  lockfile is present (hard-failing on lockfile drift instead of silently
  mutating it) and falls back to `npm install` only when no lockfile exists.

### Fixed
- **Docs/enforcement reconciliation.** `coding-rules.md` rule 6 now covers TS
  floating-promise discipline and rule 9 describes what actually runs at commit
  time vs CI; the README "What the tooling enforces" matrix gains rows for
  type-aware async rules, `tsc`, the new frontend patterns, and ESLint import
  hygiene.

### Security
- **Rename-to-skipped-extension secret bypass (audit HIGH).** `check-secrets`
  skipped files by extension (`*.png`, `*.zip`, `package-lock.json`, …), so a
  plaintext secret renamed to a skipped name passed the scan in both the hook
  and CI. The extension allowlist is removed: every tracked file's staged blob
  is now scanned as text. NUL bytes are still stripped (so they can't hide
  content — a NUL-based "binary, skip" sniff was deliberately rejected because
  it would reopen that bypass), and the existing `MAX_LINE_LENGTH` line-drop
  keeps a minified/binary blob from hanging the scan. New harness fixtures
  cover `secret.png`, `secret in package-lock.json`, and NUL+binary-extension.
- **`::error` annotation injection (audit LOW).** All four `lib/check-*`
  scripts now percent-encode the `file=` property (`%`, CR, LF, `:`, `,`) and
  the message body (`%`, CR, LF) per GitHub's workflow-command rules, so a
  crafted filename or description can't forge or truncate a CI annotation.

### Documented
- **`lint.yml.template` guardrails job: two inherent limitations** now spelled
  out in-file — it runs check scripts/configs from the PR head (defense in
  depth, not a trust boundary against hostile forks; pair with branch
  protection / scan from the base ref), and it scans the committed blob, so a
  Git-LFS pointer is scanned rather than the LFS content (add `lfs: true` if
  you keep scannable text in LFS).

### Fixed
- **`README.md` stale claims.** The size check is the staged blob's line count
  (`git show :0:<path>`), not `wc -l`; the secret scan covers *every* tracked
  file (no extension allowlist), not a vague "all files"; and the
  hook-vs-CI file-scope asymmetry (changed-only vs all-tracked) is now noted
  for all four checks, not just size.

## [v0.5.2] — 2026-05-25

### Fixed
- **Pinned actions ran on Node 20, force-deprecated 2026-06-02.** GitHub
  forces all Node-20 actions to Node 24 on 2026-06-02 and removes the
  Node-20 runtime 2026-09-16; every consumer's workflow runs were already
  emitting the deprecation annotation. Bumped the SHA pins across
  `lint.yml.template`, `test.yml`, and `shellcheck.yml` to Node-24-capable
  majors: `actions/checkout` v4.3.1 → **v6.0.2**, `actions/setup-python`
  v5.6.0 → **v6.2.0**, `actions/setup-node` v4.4.0 → **v6.4.0**. Inputs
  (`python-version`, `node-version`) are unchanged and compatible; verified
  with `actionlint` + the full test harness.

### Changed
- `README.md` install pin bumped to `v0.5.2`.

## [v0.5.1] — 2026-05-25

### Fixed
- **`lint.yml.template`: workflow was invalid for every consumer.** The
  `python` and `frontend` jobs gated execution with a **job-level**
  `if: hashFiles(...)`. `hashFiles()` is only available once a runner is
  assigned and the repo is checked out, so GitHub rejected the *entire*
  workflow file as invalid — meaning **no job ran at all**, including
  `guardrails` (the server-side mirror of the pre-commit hook). Every push
  reported a startup failure with no jobs and no annotations. File
  detection now runs in a post-checkout `detect` step; the tool steps are
  gated on `steps.detect.outputs.present`, preserving the
  skip-when-absent behavior. A frontend-only repo now shows a green, empty
  `python` job instead of a hard workflow error.

### Added
- **`tests/run.sh` + `test.yml`: workflow-validity regression guard.** The
  harness now renders `lint.yml` via `install.sh` and validates it with
  `actionlint` (pinned 1.7.12), so a job-level `hashFiles()` — or any
  context-availability error — can never silently disable CI for consumers
  again. `actionlint` is skipped locally when absent; CI always runs it.

### Changed
- `README.md` install pin bumped to `v0.5.1`.

## [v0.5.0] — 2026-05-20

### Added
- **`coding-rules.md`: "Testing" section (items 8–9).** Four-category
  baseline (linter, type-checker, test runner, property-based) every
  project picks per stack. Pre-commit runs linter + type-checker.
  Codifies what the scaffold already assumes about tooling; previously
  only described informally in tool docs.
- **`coding-rules.md`: "Observability" section (items 10–12).**
  Structured logging library (stack-specific: `structlog` for Python,
  `pino`/`winston` for TS), `snake_case_verb` event names (filterable
  strings, not prose), and request-correlation-ID binding to log
  context (`X-Request-Id` or equivalent) for cross-service tracing.
- **`coding-rules.md`: "Versioning" section (item 13).**
  Stable-additive only — adding fields/files/endpoints is free;
  renames/removals/type changes require a version bump + consumer
  notice. Silent breaking changes fail downstream, far from cause.
- **`operational-rules.md`: five new Engineering entries.**
  - *Integration tests hit a real database, not mocks.* Mocked tests
    pass against the mock, not the schema; migration drift hides.
  - *Tests cover every code path; back claims with measurement.*
    "We have tests" ≠ "this is tested." Numbers from real runs beat
    narrative correctness.
  - *No silent failures.* When work fails, log WARN+ AND surface in
    response. Catch-and-return-success is the most expensive habit
    in production code.
  - *Hold shared-resource locks for contiguous work, not per
    operation.* Per-op locking causes thrash + starvation under
    contention (GPU, DB pool, hardware port).
  - *Never print, cat, or echo secret files.* AI agents' habit of
    `cat .env` lands secrets in chat transcripts / logs forever;
    rotation cost is high. Verify by length / hash / count instead.

### Changed
- `README.md` install pin bumped to `v0.5.0`.

## [v0.4.0] — 2026-05-03

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
- `actions/setup-python` + `pip install ruff` step in `test.yml` so the
  new ruff-integration test case actually exercises lint at hook time.

### Changed
- `check-patterns` and `check-secrets` rewritten to combine all patterns
  into one ERE per scan and run a single `grep` per file as a fast-path
  filter. Per-pattern attribution only runs on files that already
  matched something. Cuts grep invocations from O(P×F) to F + matching×P
  — meaningful on the CI path where `git ls-files` feeds in thousands of
  files.

### Fixed
- `uninstall.sh` uses `git rev-parse --git-dir` (matching `install.sh`)
  so `core.hooksPath` is correctly unset in worktrees and submodules.
- Pre-commit header comment described the pattern format as
  `regex|description`; corrected to TAB-separated to match v0.3.0.
- `check-secrets` skip list extended to cover `.exe`, `.dll`, `.so`,
  `.dylib`, `.bin`, `.class`, `.pyc`, `.pyo`, `.o`, `.a`, `.parquet`,
  plus `go.sum` and `package-lock.json` / `pnpm-lock.yaml` (other
  named lockfiles fall under the existing `*.lock` glob). Cuts false
  positives and slow scans.
- `[a-z]+://` URL-with-credentials pattern in `secrets.txt` widened to
  `[a-zA-Z]+://` so the regex reads correctly without depending on
  `grep -i`.
- Stale `[[:<:]]print` example in `forbidden-patterns/README.md`
  updated to the POSIX-portable `(^|[^A-Za-z_])print` form actually
  used elsewhere in the doc.
- "Clean Python file" test fixture (`tests/run.sh` case 6) gained the
  blank line between `import logging` and the rest, which ruff I001
  requires now that the hook lints.

### Security
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
