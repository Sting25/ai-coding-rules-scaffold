# Changelog

All notable changes to this project are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [SemVer](https://semver.org/).

## [Unreleased]

## [v0.9.0] — 2026-06-30

A security-hardening release. A full multi-dimension re-audit of the scaffold's
own scanners closed one critical and several high-severity findings, and a new
installer upgrade path means existing installs pick up the fixes by just
re-running `install.sh`.

### Security
- **`check-secrets` fails closed on over-long lines (A1, critical).** A line
  longer than `MAX_LINE_LENGTH` (50k) is still dropped before the regex (the
  ReDoS guard), but the file is now reported and the commit rejected instead of
  passing with only a warning — previously a secret on a >50k line rode straight
  through, in both the hook and `--ci`.
- **`agent-precheck` no longer fails open on the block path (A2, high).** The
  block path took `SIGPIPE` (exit 141), which runtimes read as a non-2 "allow",
  so a flagged Write/Edit could slip through; it now reliably reaches `exit 2`.
- **`scaffold-allow` hardened against the bare `--` smuggle (A3, high).** The
  exemption marker no longer treats a bare `--` as a comment leader and requires
  a start-of-line/whitespace boundary, across all five exemption sites, so an
  inline `-- scaffold-allow` inside a string literal can't whitelist a real
  secret.
- **Credential filenames match case-insensitively (A4, high).** `.PEM`, `.ENV`,
  `ID_RSA`, and friends were bypassing the filename block on case-insensitive
  filesystems; the name and path are now folded to lowercase before matching.
- **Broader credential coverage (A6/A8).** Underscore-separated assignments
  (`db_password`, `client_secret`, `DATABASE_PASSWORD`), more provider key
  prefixes (SendGrid, Shopify, Square, Mailgun, Telegram, Twilio), and
  empty-username credential URLs are now caught; hex-token patterns are
  boundary-anchored to avoid SHA / UUID / lockfile-hash false positives.
  (Unquoted `key = variable` assignments remain deliberately delegated to the
  gitleaks layer to avoid false positives.)
- **`install.sh` no longer writes through a symlink (A7, high).** Scaffold files
  are replaced via `test -L` + `cp -P` backup + `rm -f` before copy, and `chmod`
  only touches regular files, so a planted symlink can't redirect a write or
  abort the install.

### Added
- **`githooks/lib/ci-changed-files`** — shared helper that resolves the PR/push
  diff as a NUL-delimited list (failing open to the whole tree when there's no
  diff base). One testable implementation called by every diff-scoped `lint.yml`
  job, instead of copy-pasted bash inside the workflow YAML. Installed by
  `install.sh`.
- **`tests/cases/10-ci-diff-scope.sh`** — regression test (12 assertions) for
  the diff-scoping: legacy grandfathered, new code gated, secrets/filenames
  caught whole-tree, and every fail-open branch (no diff base, an unresolvable
  SHA, and an erroring diff) exercised, with the internal fallback mutation-proven.
- **`operational-rules.md` rule: "Capture pre-existing issues; never silently
  drop them."** The complement to scope discipline — an out-of-scope bug, drift,
  or lint finding noticed mid-task must land on a tracked fix-list, not be
  dropped because "that's not what we're working on."

### Changed
- **`lint.yml` CI scopes its quality gates to the PR/push diff.** The `python`
  (ruff), `frontend` (eslint/prettier), and the size / forbidden-pattern /
  hygiene `guardrails` checks now run only against changed files, so installing
  the scaffold onto an existing project no longer retroactively fails its
  pre-existing code — only new/changed code is gated, matching the pre-commit
  hook's staged-files scope. The **secret + credential-filename** scans
  deliberately stay **whole-tree** (catching an already-committed secret/key is
  the point, and they're the non-overridable security boundary). Falls open to a
  whole-tree scan when there's no diff base (e.g. first push to a new repo).
- **Re-running `install.sh` is now an upgrade path.** Scaffold-owned code (the
  pre-commit hook, `.githooks/lib/*` scanners, `commit-msg`, and the `lint.yml` /
  coverage workflows) is refreshed whenever it differs from the shipped version —
  no `--force` needed — so re-running delivers security fixes. User-owned configs
  (`ruff.toml`, `eslint.config.js`, `.scaffold.toml`, the rules docs,
  `dependabot.yml`) still skip unless `--force`; `.forbidden-patterns/*.txt`
  files you've edited are kept with a drift notice (backed up to `.scaffold-bak`
  only under `--force`).
- **Workflow shell is bash-3.2-safe.** Replaced `mapfile` (bash 4+) in the
  diff-scoped jobs with the portable NUL read-loop the `check-*` scripts use, so
  the workflow runs on older / self-hosted runners too.

### Fixed
- **`frontend` lint job emits an actionable error when the eslint config is
  present but its peer deps aren't installed**, naming the exact `npm i -D …` to
  run and to commit the lockfile, instead of a cryptic config-load crash.
- **Test-harness portability** — the `agent-precheck` SIGPIPE regression test
  builds its >128 KB payload via `jq --rawfile` rather than an `--arg` string
  that hit Linux `MAX_ARG_STRLEN`, so the suite runs on both runners.
- **Documentation reconciled with the audit** — the README secret-scan and
  install tables, the `--cursor` `jq` fail-open caveat, and the
  `forbidden-patterns` README's `.svelte` coverage now match the shipped
  behavior.

### Upgrade note
- Existing installs should re-run `install.sh` to pick up the hardened scanners
  and the new `lint.yml` (which calls the new `ci-changed-files` helper).
  Re-running refreshes scaffold-owned code automatically; your configs and edited
  pattern files are preserved.

## [v0.8.0] — 2026-06-27

Audit-hardening release. Closes the self-application gap — the scaffold now
lints its own tracked files in CI — fixes a `CLAUDE.md` data-loss bug in
`uninstall.sh`, adds four security deny-patterns, and splits the test harness
back under the 500-line cap it enforces on everyone else. Also includes the
`install.sh` clobber fix previously sitting unreleased.

### Added
- **`self-lint.yml` — the scaffold now enforces its own guardrails on itself.**
  A maintainer-only CI job renders the `*.template` sources (the installable
  copies are gitignored in this repo) and runs
  `check-{size,patterns,filenames,secrets,hygiene}` over the repo's own
  `git ls-files`. Previously only `shellcheck.yml` + `test.yml` ran — neither
  scanned tracked files with the `check-*` scripts — so the scaffold could ship
  a file that violated its own rules with no signal (exactly how `tests/run.sh`
  drifted to 1135 lines, 2.27× the cap, uncaught).
- **Four new forbidden-patterns**, each functionally validated and test-covered:
  backend `verify=False` (requests/httpx TLS validation disabled); shell
  `curl -k`/`--insecure` and `wget --no-check-certificate`; secrets Docker Hub
  `dckr_pat_` tokens; frontend raw `innerHTML`/`outerHTML` assignment (XSS sink).

### Changed
- **`tests/run.sh` split under the 500-line cap.** 1135 lines → a 54-line driver
  + `tests/lib/common.sh` (shared helpers/bootstrap) + nine `tests/cases/*.sh`,
  all under 500 and sourced into one shell so the pass/fail tally is preserved.
  `shellcheck.yml` now lints the new files. Suite: 132 passed, 0 failed.
- **README leads with a scannable "What it does" section** (what it blocks + how
  it works, in bullets) before the prose rationale, and the `--force` docs now
  match behavior: each replaced file is backed up to `<file>.scaffold-bak` and
  `CLAUDE.md` / `AGENTS.md` are never overwritten.

### Fixed
- **`uninstall.sh` no longer deletes `CLAUDE.md` content past a lone
  begin-marker.** `clean_claude_md` ran `/begin/,/end/d`, which deletes to
  end-of-file when the `:end` marker is absent (a user-edited block, or an
  install interrupted between the two `printf`s), silently eating user content
  below it. It now requires **both** markers before stripping and uses a bounded
  `awk` that also removes the spacer blank line (no round-trip residue).
  +regression tests.
- **`install.sh` no longer clobbers user-owned `CLAUDE.md` / `AGENTS.md`.**
  `CLAUDE.md` is now *merged* — a marked `@AGENTS.md` import block is appended
  once if missing, and existing content is never replaced, even with `--force`
  (previously `--force` overwrote it wholesale with the pointer stub,
  destroying hand-written project memory). An existing `AGENTS.md` is likewise
  left untouched (its Project section is user-authored). For every other file,
  `--force` now backs the current copy up to `<file>.scaffold-bak` before
  replacing it, so no edit is silently destroyed. `uninstall.sh` strips only
  the marked block from a user's `CLAUDE.md` (or removes the file only when
  it's an unmodified scaffold-created pointer). +5 tests.

## [v0.7.0] — 2026-06-16

Toolchain setup: the scaffold now ships the tool *configs* its enforcement
already assumed (strict `tsconfig.json`, Prettier, Vitest, pytest+coverage),
detects and offers to install the *binaries* (safe auto-run only on an
interactive TTY), enforces `prettier --check` in the hook + CI, and adds an
opt-in CI patch-coverage gate that fails a PR when changed lines ship untested.

### Added
- **Toolchain setup (configs auto-installed by stack + detect/offer).** The
  scaffold now ships the configs its enforcement already assumed but never
  provided: a strict `tsconfig.json` (the type-aware eslint rules + `tsc
  --noEmit` depend on it), `.prettierrc.json` + `.prettierignore` (Prettier runs
  separately from eslint — `strictTypeChecked` has no stylistic rules, so there
  is intentionally no `eslint-config-prettier`), `vitest.config.ts` (skipped when
  the project already uses Jest), and `pytest.ini` + `.coveragerc` for Python
  (pytest.ini skipped when pyproject/tox already configures pytest). All install
  by stack like `ruff.toml` / `eslint.config.js`; `cp_safe` won't clobber
  existing files.
- **`prettier --check` in the pre-commit hook + CI**, guarded like ruff/eslint
  (runs only when a prettier config is present and prettier is installed,
  silently skipped otherwise; `prettier --write` fixes).
- **Detect → offer toolchain step (replaces the post-install linter smoke
  test).** `install.sh` now checks for `ruff`/`pytest` and
  `eslint`/`tsc`/`prettier`/`vitest`, and offers to install anything missing.
  Auto-install runs ONLY when safe — interactive TTY, not `--no-verify`, not in
  CI (`$CI`), and not `--no-install`; otherwise it prints the command, so CI and
  piped runs never mutate the environment. Package manager detected from
  lockfiles (`npm`/`pnpm`/`yarn`, `pip`/`uv`). New flag: `--no-install`.
- **Opt-in CI patch-coverage gate (`install.sh --coverage-gate` →
  `.github/workflows/coverage.yml`).** Fails a PR when changed lines ship
  untested (`diff-cover`, default 100% of changed lines, tunable via
  `DIFF_COVER_FAIL_UNDER`). Covers both stacks via Cobertura XML. It gates
  *execution* of changed lines, not assertion quality — documented ceiling, with
  mutation testing as the deferred follow-up in `RECOMMENDATIONS.md` ("Forcing
  tests"). Action SHAs match `lint.yml` so the pin-drift guard stays green.
- **+10 tests** (119 total): config delivery by stack, Jest/pytest skip paths,
  `coverage.yml` actionlint validity, and a regression guard that the detect/
  offer step is print-only and non-mutating without a TTY.

## [v0.6.0] — 2026-06-11

Multi-language enforcement (PHP/Go/Rust/Java/Kotlin/Ruby), broadened TypeScript
type-aware linting, a per-project `.scaffold.toml` override layer, opt-in
agent-runtime hooks (Claude + Cursor), 2025-26 supply-chain / secret-scanning
hardening, and a delta round of modern-practice deny-patterns.

### Added
- **`preserve-caught-error` (`eslint.config.js`, default-on).**
  `catch (e) { throw new Error('failed') }` destroys the original error
  cause/stack — a signature AI-agent pattern that makes production failures
  undiagnosable (fix: `new Error(msg, { cause: e })`). The rule entered
  `eslint:recommended` only in ESLint v10 (Feb 2026); pinning it explicitly gives
  v9.35+ users the same guard and removes the v9/v10 fork. (Requires ESLint
  ≥ 9.35 — the rule does not exist before that.) `no-useless-assignment` was
  evaluated alongside it and deliberately **not** added: it has open
  false-positives on TS `satisfies` and Vue SFCs, the scaffold's core audience.
- **`git --no-verify` block (`shell.txt`, default-on).** Converts an existing
  *prose-only* rule (`AGENTS.md` git discipline + `coding-rules.md` rule 9 + the
  README "`--no-verify` doesn't become the escape hatch" invariant) into a
  machine check at the agent action boundary — `agent-precheck` already feeds
  `shell.txt` to Claude `PreToolUse` and Cursor `beforeShellExecution`. Stops an
  agent from skipping the gate locally (a documented behavior: claude-code#40117).
  Scoped to a git subcommand within one pipeline segment, so a non-git
  `--no-verify` flag (e.g. `install.sh --no-verify`) doesn't match; a genuine
  agent-driven uninstall can use `scaffold-allow`. CI remains the unskippable
  backstop. +2 fixtures.
- **Svelte `{@html}` XSS deny-pattern + `.svelte` coverage (`frontend.txt`,
  default-on).** Same untrusted-HTML-injection bug class as the already-banned
  `dangerouslySetInnerHTML` (React) and `v-html` (Vue); agents reach for
  `{@html data}` the same way when told to "render this markdown." The required
  trailing space after `@html` keeps the rule off prose/`{expr}` interpolation.
  Adding `svelte` to the `# scaffold-extensions:` header also closes a silent
  gap — `.svelte` was in no header, so `console.log` / `.only` / `@ts-ignore` /
  `localhost` / TLS rules were all un-scanned inside component files. +2 fixtures.
- **Four 2025-26 secret/token shapes in `secrets.txt` (default-on).** Prefix-
  specific, low-FP additions the offline gate was missing: **AWS Bedrock** API
  keys (`ABSK…`, a 22-char anchor that is the base64 of `BedrockAPIKey` — not
  matched by the `AKIA`/`ASIA` rule), **Supabase** secret keys (`sb_secret_`, the
  new opaque RLS-bypassing format that replaced the JWT `service_role` key, so
  the `eyJ` rule no longer catches it), **OpenRouter** keys (`sk-or-v1-` — the
  embedded dashes terminate the alphanumeric run, so the legacy `sk-…{48}` rule
  provably misses them), and the **GitLab** non-PAT token family
  (`gloas-`/`gldt-`/`glrt-`/`glrtr-`/`glptt-`/`glagent-`/`glsoat-`/`glffct-`/
  `glimt-`/`glft-`/`glwt-` — OAuth/deploy/runner/trigger/agent/SCIM/feed tokens,
  all documented CI supply-chain entry points; the scaffold previously covered
  only `glpat-`). All prefixes verified against official provider docs. +4 fixtures.
- **`datetime.utcfromtimestamp()` deny-pattern (`backend.txt`, default-on).**
  CPython 3.12 deprecated `utcfromtimestamp()` in the *same* change as
  `utcnow()` (already banned) — same naive-"UTC" bug class. A steered agent that
  drops `utcnow()` can still emit this and pass the hook; the always-on regex now
  covers it (use `datetime.fromtimestamp(ts, tz=datetime.UTC)`). A commented
  opt-in `asyncio.get_event_loop()` line is added too (OFF by default — inside a
  running coroutine it legitimately returns the running loop, so a name-anchored
  ban over-fires; enable for app code standardizing on `asyncio.run()`). +1 fixture.
- **Commit-subject length cap (opt-in `--commit-msg`).** The Conventional-Commits
  hook now also rejects subjects over 100 chars (commitlint `config-conventional`
  `header-max-length` parity) — runaway subjects wrap in `git log` / GitHub and
  break changelog tooling. Independent guard, merge/revert/fixup still exempt.
  +1 fixture.
- **Agent-runtime layer extended (opt-in `--claude`).** `agent-precheck` now
  also scans **Bash** tool calls against `.forbidden-patterns/shell.txt` (a
  separate case-sensitive pass matching commit-time semantics) — blocking
  `curl|bash`, `rm -rf /`, `chmod 777` before the agent runs them, the
  highest-ROI agent hook the docs already named but didn't ship. The bundled
  `.claude/settings.json` now also sets `enableAllProjectMcpServers: false` +
  empty `enabledMcpjsonServers`, so a cloned repo's `.mcp.json` can't
  auto-approve an exfiltrating MCP server (CVE-2026-21852). +2 fixtures.
- **`AGENTS.md` docs corrected.** `AGENTS.md` is now described as the open
  cross-tool standard (agents.md) and the nested-file guidance points to nested
  `AGENTS.md` (closest-file-wins) rather than per-tool files; a new `## Checks`
  section lists the runnable commands an AGENTS.md-compliant agent self-verifies
  with (`ruff check .`, `eslint`/`tsc`, `git hook run pre-commit`).
- **Hidden-Unicode guard in `check-hygiene` (default-on).** A third hygiene
  check scans each staged text blob for invisible control characters: bidi
  overrides (CVE-2021-42574 "Trojan Source"), zero-width chars, and the Unicode
  tag block — the vectors behind the Feb-2025 "Rules File Backdoor", which
  weaponizes invisible Unicode inside the very agent-read files this scaffold
  ships (`AGENTS.md`, `coding-rules.md`, `.forbidden-patterns/*`). Matched as
  UTF-8 byte sequences under `LC_ALL=C` (BSD-grep / bash-3.2 safe); binary blobs
  are skipped, a legitimate leading BOM is allowed, findings are hex-sanitized so
  the raw invisible bytes never hit the log, and `scaffold-allow` exempts a line.
  New `hidden-unicode` override id (disable / `warn` for legit RTL repos). +4
  fixtures. `check-hygiene` added to the maintainer shellcheck CI list.
- **CI / supply-chain hardening (default-on).** Post-Shai-Hulud / tj-actions
  mitigations across the shipped workflows + Dependabot config: a **7-day
  Dependabot `cooldown`** (a yanked malicious release is gone before the PR
  appears; security updates bypass it), **`npm ci --ignore-scripts`** in the CI
  frontend job (lint/tsc never need a dep's install hooks; documents a
  `npm rebuild` escape hatch for native deps), and **`persist-credentials: false`**
  on every `actions/checkout` (don't leave `GITHUB_TOKEN` in `.git/config`).
  The scaffold's own `test.yml` gains a pinned, offline **zizmor** static audit
  of all workflows (incl. rendered templates) — maintainer CI only, not shipped
  to consumers — so a re-introduced unpinned action or credential-persist fails
  the build. Two `SECURITY_AUDIT.md` Low items move Open → Partial.
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

### Documented
- **Six new `RECOMMENDATIONS.md` entries** (dated, with explicit "adopt if"
  triggers, per the file's convention — deliberate omissions, not shipped
  features): `ruff` FURB group; commit-time Python type-check via `ty`/`pyrefly`;
  Biome/oxlint vs ESLint tradeoffs; pinning the CI `ruff` version (with the
  honest note that Dependabot won't bump a workflow-embedded literal);
  SLSA/OIDC trusted publishing; and `release-please` for automated SemVer
  releases (cross-linked from the `--commit-msg` opt-in bullet).

### Changed
- **`coding-rules.md` rule 12** now prefers the W3C `traceparent` header
  (OpenTelemetry's auto-propagated default) over `X-Request-Id` (the 2018-era
  norm, kept as the lighter fallback) — an agent following the old text would
  hand-roll request-id plumbing that collides with what OTel SDKs already
  propagate. Substance (one correlation ID across all log lines) unchanged.
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
