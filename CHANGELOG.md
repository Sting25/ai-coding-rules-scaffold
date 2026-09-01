# Changelog

All notable changes to this project are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [SemVer](https://semver.org/).

## [Unreleased]

### Added

- **`_backup` warns when an overwritten file carried a `# Repo adaptation:`
  marker (#127).** Root cause: before #110, `coverage.yml`/`tests.yml`/
  `gitleaks.yml` installed via `cp_scaffold` (unconditional refresh on
  drift), so a plain re-run silently discarded a hand-authored line
  explaining why a project's copy intentionally diverges from the shipped
  template, no `--force` needed to trigger it. #110 already fixed the
  no-force case for those three files by switching them to
  `cp_scaffold_preserve` (kept in place, drift note printed instead). The
  gap this closes is what's left: a *wanted* overwrite, either
  `cp_scaffold`'s unconditional refresh (`.githooks/pre-commit` and other
  scaffold-owned code) or `--force` on a drift-preserving file, still
  silently dropped a marked block with nothing but a generic "backed up:"
  line. Every `cp_*` overwrite funnels through the shared `_backup` helper,
  so the fix lives once there: count and name any `# Repo adaptation:`
  line in the file about to be replaced and print it, pointing at the
  `.scaffold-bak` that already holds the full content. Chose a loud
  pointer over attempting to re-splice the marked block into the freshly
  rendered template, text-level reinsertion is fragile across template
  versions and this codebase already prefers "keep + notify" over
  auto-merge for exactly this class of problem (`cp_pattern`,
  `cp_scaffold_preserve`).

## [v0.13.0] - 2026-09-01

A catch-up release: `main` had drifted 114 commits ahead of the last npm
publish (#126), so `--zizmor-ci`, `--socket-ci`, `--npm-cooldown`, and
`--claude-skill` existed on the repo but were unreachable via `npx`. This
release ships them, plus the Cursor `beforeReadFile` credential guard, the
paired-artifact half-install detector, the byte-size large-file guard, the
dependency-review AGPL gate, and two new operational-rules.md entries.

### Added

- **`operational-rules.md`: eight new entries adopted from issue #120.** A
  conditional must not be a shell function's last command under errexit; assert
  the positive outcome, not the absence of the symptom; in cross-platform
  fallback chains, the noisy-failure variant goes last; version bumps travel
  only in release commits; a check that can pass by luck is failing; track
  work in at most two places; one writer per repo at a time, check before
  merging; end every session with a rules retrospective.
- **`operational-rules.md`: "Choose the strongest approach before starting,
  not the fastest one to finish" (#124).** Decide between the correct/robust
  approach and the quick one before writing the fix, not after: by the time
  work is done and under review, the fast path is already built and sunk cost
  pushes toward keeping it, so the decision has to happen at the fork, not as
  a postmortem question.
- **Cursor `beforeReadFile` credential-path guard.** `install.sh --cursor` now
  wires `.githooks/lib/agent-precheck` to Cursor's `beforeReadFile` hook too
  (previously only `beforeShellExecution` was wired), denying reads of
  credential files (`.env`, `*.pem`, `~/.ssh/**`, `~/.aws/**`, …) via
  `.githooks/lib/credential-read-patterns.txt` — the Cursor sibling of
  Claude Code's native `permissions.deny` credential-file list, closing a
  previously-documented gap.

- **`scaffold-doctor.sh` detects half-installed paired artifacts (#96).** A
  new "paired artifacts" section, and a matching end-of-run check in
  `install.sh` itself, flag when only one half of a two-part guardrail is on
  disk: `.coveragerc` without `.github/workflows/coverage.yml` (and the
  inverse, on a Python project), a local gitleaks pre-commit pass without the
  gitleaks CI workflow (and the inverse, which is a valid CI-only posture),
  and the `tests.yml`/`coverage.yml` selection state from #97 (both installed
  runs the suite twice; neither installed while `lint.yml` is present means
  no test ever executes in CI). Genuine half-installs are gaps (affect
  `scaffold-doctor.sh`'s exit status); deliberate or default-shaped states
  are notes. The detection logic lives once in `install-lib.sh`'s
  `check_paired_artifacts`, shared by both callers so the wording can't
  drift between them. `install.sh`'s own reporting is advisory only and
  never changes its exit status.
- **`self-lint.yml` runs a real eslint pass over the shipped
  `eslint.config.js.template` (#83).** The repo lints shell, workflows,
  Python, and its installed docs, but never executed the eslint config it
  ships; a rule violation once sat in the template unnoticed for months.
  The self-lint workflow now installs the template's documented peer set
  (version-pinned) and lints both a sample file and the config file itself,
  so a template that breaks its own rules fails CI here instead of in a
  consumer's repo.
- **`install.sh --dependency-review` wires up the dependency-review CI gate
  (#113).** `.github/workflows/dependency-review.yml.template` shipped and
  was documented in TECHNICAL.md, but no installer call site referenced it,
  so it was never installed into any consumer project. A dedicated opt-in
  flag now installs it via `cp_scaffold_preserve` (same drift-preserving
  policy as `--gitleaks-ci`'s `gitleaks.yml`), kept opt-in rather than
  default-on because the action errors on a private repo without GitHub
  Advanced Security. This repo now installs its own rendered copy at
  `.github/workflows/dependency-review.yml`, since the repo is public and
  GitHub's Dependency Graph is on by default here.
- **Byte-size guard for accidentally committed large binaries
  (`check-large-files`, P-15).** A new `lib/check-large-files` measures each
  staged file's blob size and rejects anything over a 500 KB cap (raisable
  per project via `.scaffold.toml [large-files]`), wired into the
  pre-commit hook, `lint.yml`'s CI mirror, and this repo's own
  `self-lint.yml`. Distinct from `check-size`'s 500-line cap, which skips
  binary/media extensions before it ever measures and so let a large video,
  model checkpoint, database dump, or zipped export through untouched: this
  check has no extension skip list and measures every staged file's byte
  size instead.
- **Opt-in zizmor and Socket Firewall CI gates (`install.sh --zizmor-ci`,
  `--socket-ci`).** Two new templates, same opt-in posture as
  `--gitleaks-ci` and `--dependency-review`: `zizmor.yml` runs a static
  audit of the project's own GitHub Actions workflows (unpinned `uses:`
  refs, template-injection, credential-persisting checkouts, over-scoped
  `GITHUB_TOKEN`), and `socket-security.yml` routes its `sfw`-prefixed
  package installs through Socket Firewall so a malicious or
  typosquat/slopsquat package is blocked at install time, before its code
  ever runs, instead of only reported on afterward. Both install via `cp_scaffold_preserve`, the same
  drift-preserving policy as the scaffold's other opt-in CI workflows.
- **`dependency-review` gains a conservative AGPL deny-list license gate.**
  The action's own license-compliance inputs, left unused by the shipped
  template until now, fail the PR on a deny-list of AGPL SPDX ids: the one
  license family that can force a consumer's own product open, with fewer
  false positives for this audience than a broader allow-list would
  produce.
- **Agent-addressed "not enabled" summary in `install.sh` and
  `scaffold-doctor.sh`.** Responds to a real incident: an agent hand-copied
  files instead of running the installer, hooks ended up unarmed, and a
  secret shipped that the disabled layers would have caught.
  `install.sh`'s closing `Next:` block now lists every opt-in protection
  not enabled on this run, each with its exact enable command, opening
  with a note addressed to the installing agent asking it to relay the
  list before treating the install as finished. `scaffold-doctor.sh` gets
  a matching "Protections not enabled" section so the same question has
  one direct answer at any later point, not only at install time.
- **New agent-facing rules: session-start doctor check, restore points,
  untrusted content, and slopsquatting.** `AGENTS.md` now asks an agent to
  run `scaffold-doctor.sh` (or `npx ai-coding-rules-scaffold doctor`) at
  the start of a session to catch an unarmed hook after a clone; requires
  a tagged restore point before risky multi-step work, with history shown
  before any recovery attempt; and adds an "Untrusted content" section
  treating fetched pages, repo files, and tool output as data, never as
  instructions. `coding-rules.md` adds rule 14, verifying a new dependency
  is the real package, not a hallucinated or pre-registered look-alike,
  before it reaches a manifest. README's "Already have commit history?"
  section recommends a one-time full-history secret scan (`gitleaks git
.`) for a repo that predates the scaffold install.
- **Opt-in npm install-layer cooldown (`install.sh --npm-cooldown`,
  #117).** A new `.npmrc.template` sets `min-release-age=7`, delaying how
  soon a freshly published npm package version becomes installable, needs
  npm `>= 11.10.0` (older npm just warns and ignores the unrecognized key,
  fail-open). Matches `.github/dependabot.yml`'s existing 7-day cooldown,
  which only covers Dependabot's own PRs, not a manual `npm install` an
  agent or developer runs; this closes that gap with the same number.
  `.npmrc` is user-owned (`cp_safe`), so a re-run never overwrites a
  project's own copy without `--force`.
- **Optional Claude Code Skill packaging (`install.sh --claude-skill`,
  #118 part 2).** Installs `.claude/skills/coding-rules/SKILL.md`, a Skill
  that tells Claude Code to read the project's installed `coding-rules.md`
  and `operational-rules.md` in full on demand (before writing/editing
  code, before a commit, or when asked about this project's conventions).
  A third, distinct loading path alongside the always-installed AGENTS.md
  summary (imported into every turn, but only links to the full files by
  name) and `--claude`'s runtime hooks (block a bad tool call as it
  happens); combine freely with either. User-owned (`cp_safe`).

### Changed

- **Test execution in CI is default-on (#97).** A plain `install.sh` run now
  installs `.github/workflows/tests.yml` (pytest/vitest, no coverage
  threshold) instead of leaving CI lint-only with zero tests ever executing.
  `--coverage-gate` swaps `tests.yml` for `coverage.yml` (same tests, plus the
  patch-coverage gate) rather than installing both, so tests never run twice
  in the same CI run. New `--no-test-workflow` opts out entirely for a repo
  that genuinely cannot run tests in CI, with a loud recorded skip in the
  install summary. The installer's end-of-run summary now states plainly
  which of the three states a repo ended in.
- **`coverage.yml` installs the project before running pytest, and gates the
  vitest job on vitest actually being declared (#96).** The pytest job
  previously installed only `pytest` itself, so any project whose tests
  import the package under test failed at collection; it now runs
  `pip install -e ".[dev]"` (falling back to `pip install -e .`, plus any of
  `requirements.txt`, `requirements-dev.txt`, or `requirements/dev.txt` that
  exist) first, and only when the project actually has a `[project]` table
  or a `setup.py` (a pyproject.toml holding only tool config is skipped
  rather than hard-failed). The frontend job previously ran on any
  `package.json`; it now only runs when `vitest` is actually declared in
  `dependencies`/`devDependencies`/`scripts.test`, so a repo that ships
  `package.json` for lint tooling only no longer hard-fails the job. Both
  fixes are also applied to the new `tests.yml`.
- **Fixed a real CI-breaking bug in the shipped `tests.yml.template` before
  it ever ran in the wild:** the requirements-file install loop's last
  statement was `[ -f "$req" ] && pip install -r "$req"`, and under the
  `bash -e` a `run:` step uses, that construct's own exit status (1, from the
  failed file test) became the whole step's exit status whenever the last
  candidate file was absent, which is nearly always. The default pytest job
  would have failed for virtually every Python consumer. Fixed to
  `if [ -f "$req" ]; then pip install -r "$req"; fi`, verified by running the
  extracted step body under `bash -e` with pyproject-only, requirements.txt-
  only, and no fixtures at all: all three now exit 0.
- **Every tracked markdown file must pass the shipped prettier config
  (#82).** The self-lint gate previously covered only the docs installed
  into consumer projects; README.md, CHANGELOG.md, RECOMMENDATIONS.md and
  four more tracked files failed the config the scaffold itself ships. All
  tracked markdown is now formatted, and the gate covers the whole set
  instead of the installed subset.
- **All installer-managed CI workflows are now drift-preserving (#110).**
  `tests.yml`, `coverage.yml` and `gitleaks.yml` follow the policy #105 set
  for `lint.yml`: a customized file is kept with a `note (drift):` line and
  replaced (with backup) only under `--force`. The old pre-existing-version
  warning for `tests.yml`/`coverage.yml` was folded into the drift note
  rather than printed alongside it. The case-21 drift tests were
  generalized to cover all four workflow files.
- **self-lint installs its npm tooling from committed lockfiles (#108).**
  The prettier and eslint gates now `npm ci` against
  `.github/self-lint/{prettier,eslint}/package-lock.json` instead of ad-hoc
  `npm install pkg@version` steps, so zizmor 1.26+'s `adhoc-packages` audit
  passes ahead of the next pin bump. The lockfile directory is excluded
  from the npm package.
- **The cases/17 eslint syntax check is a standalone, mutation-tested
  script (#111).** Extracted to `tests/lib/eslint-syntax-check.sh` and
  exercised under a curated node-free PATH, proving the CI-fails and
  local-skips branches instead of trusting them.

### Fixed

- **`install.sh` no longer silently overwrites a customized `lint.yml`
  (#105).** A re-run used to back up and refresh a drifted
  `.github/workflows/lint.yml`, discarding consumer CI setup (measured in a
  real downstream repo: 23 deletions, 0 insertions, reported as a bare
  `updated:` line). The workflow file is now drift-preserving like the
  pattern files: kept in place with a `note (drift):` line, and replaced
  (with backup) only under `--force`.
- **The six optional pre-commit lint checks announce their skips (#105).**
  ruff, eslint, prettier, tsc, `php -l` and phpcs used to skip with no
  output at all when their tool was off `PATH`, so a green hook run was not
  evidence that lint ran. Each check now prints a one-line note to stderr
  when staged files matched but the tool was unavailable; exit codes are
  unchanged, so a missing optional tool still never blocks a commit.
- **The eslint-template syntax check in `tests/cases/17` can no longer skip
  invisibly in CI (#85).** When `GITHUB_ACTIONS` is set and node is absent,
  the case now fails loudly instead of printing a local-style skip line
  that is indistinguishable from a pass in the final tally.
- **`RELEASING.md` states the required release commit message (#92).** The
  prep commit must be `chore(release): vX.Y.Z`; the historical bare
  `release:` type is rejected by the shipped commit-msg hook.
- **`local.d/README.md.template` is formatted, gated, and truthful
  (#107).** The shipped doc failed the prettier config, escaped the
  markdown gate (the `*.md` glob misses `.template` files), and still
  claimed CI workflows are refreshed on re-run. It now passes the config,
  is copied into the gate like `AGENTS.md.template`, and describes the
  drift-preserving policy.
- **The consumer PEERS list includes `@eslint/compat` (#109).** The shipped
  eslint config imports it, but the `npm i -D` hint in `lint.yml.template`
  (and its copy in `install-verify.sh`) omitted it, leaving consumers one
  package short after following the error message.
- **`check-hygiene`'s BOM strip and hidden-unicode scan no longer hang on a
  large file (c23f30f).** Under bash 3.2 (macOS's system bash) in a
  multibyte-aware locale, the pattern-match BOM strip was catastrophically
  slow: measured ~77 seconds on one 820 KB text file, which could stall the
  pre-commit hook and CI on any repo committing a large text file near the
  `check-large-files` cap. Fixed by forcing `LC_ALL=C` for the script's own
  bash-internal length/substring/pattern-match semantics and switching the
  BOM strip from a pattern match to an index-based check-and-slice, which
  never invokes bash's glob matcher; measured 0.002s-0.07s on the same input
  after the fix.

## [v0.12.0] — 2026-08-21

A release about the difference between a guardrail being _installed_ and a
guardrail being _armed_. `scaffold-doctor` reports, for every check the
scaffold ships, whether the mechanism that makes it actually execute is in
place — `core.hooksPath` wiring, executable bits, pattern data, opt-in
surfaces and their external tools. Mutation-testing the doctor immediately
found a real hole in the shipped secret patterns (`AWS_SECRET_ACCESS_KEY`),
which is fixed here too. `install.sh` also gave up its post-install toolchain
step to a sourced module, having reached the 500-line cap it enforces on
everyone else.

### Added

- **`scaffold-doctor.sh` — checks whether an installed scaffold is armed, not
  just present.** `install.sh` reports what it _wrote_; that's a different
  question from whether the guardrails it wrote actually _run_, and the gap
  between the two is where this scaffold's worst bugs have lived: issue #76
  was a `grep -r` that silently scanned one file instead of a tree, and issue
  #72 was a check whose call site got reset on upgrade while the check script
  stayed on disk as decoration. Both were present and neither was running,
  and nothing said so.

  The doctor never reports "file exists." For each guardrail it reports
  whether the mechanism that makes it execute is in place, as `✓` armed, `✗`
  gap (installed but inert — a commit that should be blocked isn't), or `!`
  note (a deliberate off-switch, or an opt-in surface not opted into; notes
  never affect the exit status). It covers `core.hooksPath` wiring — the
  single highest-value check, since `install.sh` deliberately leaves a
  foreign hooksPath such as Husky's `.husky` alone and only warns, so
  "installed but never wired" is a state `install.sh` itself can leave
  behind — the hook entry point's executable bit, the five shipped
  `lib/check-*` scripts, `.forbidden-patterns/` and `secrets.txt` (measured
  on a real fixture: once `secrets.txt` is absent, staging a genuine
  `AKIA…` AWS access key ID and running the hook exits 0 with no output at
  all), the opt-in `check-gitleaks`/`agent-precheck` surfaces and their
  external tool dependencies, `.githooks/local.d/` project-local checks
  (where the executable bit is the on/off switch, so a disabled entry is a
  note, never a gap), and `.scaffold.toml` overrides going silently ignored
  when `lib/scaffold-config` is missing.

  Exit status: `0` with no gaps, `1` with at least one, `2` on usage error or
  outside a git repository. Run it directly (`./scaffold-doctor.sh`, from
  anywhere inside the working tree) or via `npx ai-coding-rules-scaffold
doctor`; `--quiet` prints only gaps plus the summary line, for CI or
  pre-flight use.

- **Shell-only install mode (`install.sh --shell`) ([#65]).** For projects with
  no Python or TS/JS manifest — plain bash/sh, `shellcheck`-linted — installs
  the git hooks, guard checks, and the shell-relevant plus language-agnostic
  pattern files (`shell.txt`, `secrets.txt`, both of which already shipped in
  every mode) while skipping every Python/TS config template. There is nothing
  for `ruff.toml` or `tsconfig.json` to configure in such a project.

  Auto-detect falls back to shell mode on its own: no
  `pyproject.toml`/`requirements.txt`/`setup.py`/`package.json`, but at least
  one `*.sh`/`*.bash` file, selects it without the flag. Tracked files are
  checked first (the same `git ls-files` fallback the shipped
  `lint.yml.template` php job uses when there's no `composer.json`), then the
  working tree, since `install.sh` is routinely run before the first commit. A
  manifest always wins, so a `package.json` project that also ships build
  scripts is still a frontend install. A repo with neither still errors rather
  than guessing.

  `shellcheck` gets a print-only presence hint, deliberately **not** an
  auto-install offer: it has no single canonical package manager across
  platforms, unlike ruff (pip) and eslint (npm) where the detected manifest
  names the installer unambiguously.

  Works through `npx ai-coding-rules-scaffold --shell` too — `bin/cli.js`
  passes arguments straight through with no allowlist.

- **`.githooks/local.d/` — a real extension point for project-local checks
  ([#72]).** Any executable in that directory runs as part of the guardrails, in
  both the pre-commit hook and the CI `guardrails` job, under the same contract
  as the shipped `lib/check-*` scripts: the NUL-delimited file list on stdin,
  `--ci` as `$1` in CI, non-zero exit blocks. The hook feeds it the staged list;
  CI feeds it the PR/push diff, matching the scoping of the other quality gates
  so installing onto an existing repo never retroactively fails legacy code.

  `install.sh` never writes into the directory — only a non-executable
  `README.md` documenting the contract, and that through `cp_safe`. The
  executable bit is the on/off switch, so `chmod -x` disables a check without
  deleting it; for that reason the CI job deliberately does **not** `chmod +x`
  the directory the way it does `lib/*`, which would both re-arm a disabled
  check server-side and execute the README.

  This is the durable half of the [#72] fix: before it, the only place to wire
  in a project-local check was `.githooks/pre-commit` or
  `.github/workflows/lint.yml`, both scaffold-owned and refreshed on upgrade.

### Changed

- **`install.sh`'s post-install toolchain check moved to `install-verify.sh`
  ([#84]).** `install.sh` had reached 497 lines against the scaffold's own
  500-line module-size cap — a cap it enforces on every project it installs
  into, so the installer has to obey it too. The next change to that file would
  have had to either shrink something or weaken the check, and weakening a
  guardrail to fit is the one move this repo's rules rule out.

  The extracted module is the whole post-install toolchain step
  (`js_install_cmd`, `py_install_cmd`, `offer`, and the `--no-verify`-gated
  body), now behind a single `run_toolchain_verify` call. It is SOURCED, not
  executed, on exactly the same contract as `install-lib.sh`: it runs in
  `install.sh`'s shell with its globals (`MODE`, `VERIFY`, `NO_INSTALL`) and its
  `set -euo pipefail`. Behavior is unchanged; `install.sh` drops to 419 lines.

  `tests/cases/11-npm-bundle.sh` derives its required-file list by grepping
  `install.sh` for `$SCAFFOLD_DIR/...` paths, so the new module became a
  required npm-bundle entry the moment it was sourced — `package.json` `files`
  is updated to match, and `shellcheck.yml`'s explicit file list too, since that
  list names root scripts individually rather than globbing.

- **New operational rule: "Record every skip, deferral, and flag before moving
  on."** The existing "capture pre-existing issues" rule covers what a session
  NOTICES; this covers what it DECIDES — a skipped test, a check that no-op'd
  because its tool was absent, an unanswered question, a workaround taken "for
  now", scope deliberately not taken. Each lands somewhere durable at the moment
  it happens, with why and what would unblock it, because chat is not durable and
  a PR description only counts if the item also exists outside it.

  Applied to itself immediately: the four items this session deferred are filed
  as [#82], [#83], [#84] and [#85] rather than left in PR bodies.

- **The pre-commit hook distinguishes _untracking_ a pattern file from
  _deleting_ it ([#65]).** A staged `.forbidden-patterns/*.txt` deletion used
  to hard-fail unconditionally, but `git rm --cached` (untrack, keep the file
  on disk, ignore it via `.git/info/exclude`) is a legitimate local-only-tooling
  move. Every check reads its pattern config from the **working tree** — never
  from the index — so a file still on disk keeps the scanner fully armed. The
  hook now fails only when the file is also gone from (or unreadable on) disk,
  and warns on a pure untrack.

  This does not reopen the neutering paths closed in v0.9.0: a config that is
  gone, gutted to zero patterns, or renamed away still fails, and server-side
  an untracked config is absent from the repo entirely, where
  `check-secrets --ci` fails closed. The warning says so explicitly.

  Four cases cover it, mutation-proven in both directions — including one that
  asserts the _premise_ rather than the behaviour: untracking the config while
  staging a real secret must still be caught, so the suite turns red if a check
  ever starts reading pattern config from the index.

### Fixed

- **The secret scanner now catches a hardcoded `AWS_SECRET_ACCESS_KEY`
  ([#87]).** The generic hardcoded-credential rule required its keyword to sit
  immediately before the `=` or `:`, so `secret` matched and then wanted the
  separator but found `_ACCESS_KEY`. The AKIA rule above it covers the AWS
  access key _ID_; nothing covered the paired _secret_, which is the half that
  actually grants access — and `AWS_SECRET_ACCESS_KEY` is its canonical
  spelling in every AWS SDK and CI config.

  Measured before the fix, against a fresh `install.sh --shell` project:
  `AWS_SECRET_ACCESS_KEY = "wJalr…"` and `aws_secret_access_key: "wJalr…"` both
  committed clean (hook exit 0), while `secret_key = "…"`, `api_key = "…"` and
  a bare `AKIA…` were all blocked. Adds `secret[-_]?access[-_]?key` to the
  alternation, ordered longest-first so the rule behaves identically in a
  leftmost-first engine (PCRE, and anything this file is copied into) as under
  POSIX leftmost-longest `grep -E`.

  Both directions are tested: the assignment is rejected, and `secret_name =
"billing-prod-key-name"` — an identifier that merely _contains_ "secret",
  with a value long enough to clear the 16-char floor — still passes.

- **Whole-tree checks no longer break on gitignored content ([#76]).**
  `AGENTS.md` prescribes whole-tree local commands (`npx eslint .`, `pytest`),
  but the configs installed beside them enumerated their exclusions instead of
  deriving them, and neither honoured `.gitignore`. Anything on disk but not in
  git — a vendored toolchain, an agent worktree, an extra checkout — was inside
  the blast radius. CI never showed it (fresh checkout, diff-scoped), so the
  documented local gate and the real gate disagreed.

  Both halves shared one signature: a config that reads as scoped and behaves as
  whole-tree, without announcing the fallback.

  **eslint** now derives its ignores from `.gitignore` via `includeIgnoreFile`
  from `@eslint/compat` — ESLint's own supported mechanism, added to the
  documented peer install and guarded with `existsSync` so a repo without a
  `.gitignore` still loads its config. Reproduced the reported failure first: an
  agent worktree carrying its own `eslint.config.js` but no `node_modules` made
  ESLint die with `ERR_MODULE_NOT_FOUND` and lint **nothing** (exit 2) — a
  guardrail that hard-fails on unrelated content is one people learn to skip.
  After the change the same tree lints clean, and real source is still checked.

  **pytest**: `install.sh` now detects a pytest config in a SUBDIRECTORY and
  declines to write a root `pytest.ini`. The old guard was root-only by
  accident — `grep -r` does not recurse for a file argument, only a directory —
  so in a monorepo (`backend/pyproject.toml`) it saw nothing, wrote a root
  `pytest.ini` whose `testpaths = tests` matched nothing, and pytest fell back to
  collecting from rootdir: inert _and_ shadowing the real config (losing e.g.
  `asyncio_mode`). Installing without a `./tests` now warns that collection goes
  whole-tree, and the template ships `norecursedirs` — re-listing pytest's
  defaults, since setting the key replaces rather than extends them, and
  deliberately conservative because a too-broad entry silently stops collecting
  real tests, which is worse than collecting too many.

  Also fixes a pre-existing violation surfaced by actually running eslint on the
  shipped config: `eslint.config.js.template` failed its own `import-x/order`
  rule and had since it was written, because nothing in this repo lints JS.

  Suite 252 → 260, every assertion mutation-proven.

- **`coding-rules.md` and `operational-rules.md` now pass the prettier config the
  scaffold ships beside them ([#73]).** Both land in a consumer's project root
  next to a `.prettierrc.json` this scaffold also writes, and the shipped
  `lint.yml` runs `prettier --check` over every changed file — but both docs
  failed that config, on `*Anchor:*` vs `_Anchor:_` emphasis and missing blank
  lines after headings.

  Diff-scoping did not save the consumer, because the README tells them to edit
  one of the offenders ("add a Project-specific section to `coding-rules.md`").
  Following the documented workflow put a scaffold-authored file in the changed
  set and produced a red format check, on prose the consumer never wrote, on the
  first commit after install. Formatting-only change — the prose is byte-identical
  once emphasis markers and blank lines are normalized.

  They are **not** added to `.prettierignore.template`, which the issue raised as
  an alternative. `install-lib.sh` classifies the rules docs as `cp_safe` —
  USER-OWNED, never auto-replaced — so by the scaffold's own ownership model they
  are the consumer's files, not vendored content to exempt. The right fix is to
  ship them already correct, then let the consumer's own additions be format-
  checked like anything else they write.

  `self-lint.yml` gained a step that enforces this, since nothing else in this
  repo runs prettier and a one-off reformat would rot. It checks the docs under
  their INSTALLED names in a temp dir: prettier picks its parser from the
  extension, so `AGENTS.md.template` is not seen as markdown in place and would
  silently pass unchecked. Scope is the installed set only — `README.md`,
  `CHANGELOG.md` and `RECOMMENDATIONS.md` also fail this config but never reach a
  consumer's tree, so no consumer CI checks them and reformatting them would be
  churn without a bug.

- **`install.sh` no longer destroys a locally-edited scaffold file without a
  trace ([#72]).** `cp_scaffold` refreshes scaffold-owned code on a plain re-run
  — that is how upgraders receive security fixes — but it took a backup only
  under `--force`, justified in its own header as "the prior bytes are scaffold
  code, recoverable from git history and the scaffold repo". That premise holds
  for an untouched destination and fails for an edited one, and nothing tested
  which it was.

  The two files most likely to be edited were `.githooks/pre-commit` and
  `.github/workflows/lint.yml`, because they were the only place to wire in a
  project-local check. The symptom was silent: the local check script stayed on
  disk, its call sites were reset, nothing errored, and the guardrail became
  decoration until someone noticed by chance.

  Every `cp_scaffold` overwrite now backs up to `<file>.scaffold-bak` first and
  prints a `backed up:` line, which is the signal that was missing. The refresh
  itself is unchanged, so upgrades still deliver fixes. Cost is a backup file
  beside each scaffold file that actually changed in the upgrade. If all 99
  backup slots are taken, that one file is skipped rather than overwritten
  unbacked (same policy as `cp_safe`/`cp_pattern`), with an error saying so.

  `uninstall.sh` removes the `local.d/README.md` if unmodified and clears the
  directory only when empty — a project's own checks are never scaffold files to
  remove, not even under `--all`.

  Suite 239 → 246; all four behaviours (the block, the `chmod -x` disable, the
  backup, and the CI loop) mutation-proven in both directions.

- **The patch-coverage gate no longer passes a PR whose tests are failing
  ([#71]).** `coverage.yml.template` ran both test steps with `|| true`. The
  intent was narrow and sound — `pytest` exits 5 when it collects nothing, and
  an empty suite should not mask the `diff-cover` verdict that is the actual
  gate — but `|| true` swallows exit 1 just as happily, so a PR with failing
  tests produced a green check.

  It was worse than merely not gating on failure. A failing test still executes
  the lines it touches, so those lines still land in `coverage.xml`; a PR whose
  new code was covered only by a red test therefore **passed** the patch-coverage
  gate on the strength of that very test. And since the job is named `coverage`
  and may be the only one invoking `pytest`, a consumer could reasonably read it
  as a test gate it was not.

  Now only `pytest`'s exit 5 is tolerated; 1 (failed), 2 (interrupted), 3
  (internal error) and 4 (usage error) all fail the job. `vitest` has no
  equivalent no-tests code, so its step drops `|| true` and gains
  `--passWithNoTests`, which handles the empty case by exiting 0.

  Written as `pytest … || rc=$?`, not `pytest …; rc=$?`: a `run:` step's default
  shell is `bash -e`, under which the latter exits at `pytest` before the
  assignment is reached — failing the job on exit 5 and undoing the tolerance
  the block exists to provide. `cases/16` runs the step's real shell body,
  lifted out of the shipped YAML, under `bash -e` against a fake `pytest`, and
  catches exactly that mistake.

  Suite 239 → 245.

- **`check-secrets` matches token-shaped rules case-sensitively ([#67]).**
  Every rule used to be matched with `grep -i`. The AWS key-ID rule widened to
  `(AKIA|ASIA|ABIA|ACCA)…` in v0.11.0, and `ACCA` is composed entirely of hex
  characters — so case-folded it matched inside ordinary SHA-256 digests, and
  any repo with a lockfile could fail the whole-tree scan on content holding no
  credential at all, over a message telling the reader to "rotate immediately".
  (`AKIA`/`ASIA`/`ABIA` each contain a non-hex letter and cannot collide; the
  Twilio `AC` SID prefix is all-hex and was one anchor away from the same bug.)

  `secrets.txt` rules now accept a leading `(?-i)` marker that `check-secrets`
  strips and turns into a case-sensitive match. Vendor key prefixes, base64
  segments (JWT `eyJ`, Bedrock, PyPI) and the uppercase PEM banner carry it:
  those formats are case-sensitive by specification, so folding case could
  never add a true positive, only false ones. Keyword-shaped rules
  (`password =`, `secret_key`) and the URL-scheme rules deliberately keep `-i`,
  since they match human-written prose where case genuinely varies.

  The fast pre-filter stays case-insensitive on purpose: it only decides which
  files get a closer look, so `-i` keeps its match set a strict superset of the
  per-rule pass and cannot drop a file a case-sensitive rule would have hit.

  Backward compatible — a rule without the marker behaves exactly as before, so
  an un-upgraded consumer `secrets.txt` is unaffected until its patterns are
  refreshed. Suite 227 → 230, all three cases mutation-proven.

[#65]: https://github.com/Sting25/ai-coding-rules-scaffold/issues/65
[#67]: https://github.com/Sting25/ai-coding-rules-scaffold/issues/67
[#71]: https://github.com/Sting25/ai-coding-rules-scaffold/issues/71
[#72]: https://github.com/Sting25/ai-coding-rules-scaffold/issues/72
[#73]: https://github.com/Sting25/ai-coding-rules-scaffold/issues/73
[#76]: https://github.com/Sting25/ai-coding-rules-scaffold/issues/76
[#82]: https://github.com/Sting25/ai-coding-rules-scaffold/issues/82
[#83]: https://github.com/Sting25/ai-coding-rules-scaffold/issues/83
[#84]: https://github.com/Sting25/ai-coding-rules-scaffold/issues/84
[#85]: https://github.com/Sting25/ai-coding-rules-scaffold/issues/85
[#87]: https://github.com/Sting25/ai-coding-rules-scaffold/issues/87

## [v0.11.0] — 2026-07-19

A code + security review pass (multi-dimension, each finding adversarially
verified) closing 30 confirmed findings plus one new bypass surfaced while
fixing them. Highlights: a high-severity installer symlink write-through, two
one-commit ways to neuter the secret scanner, and a NUL-injection bypass that
affected every scanner on macOS/BSD. The test suite grows 199 → 227, every new
case mutation-proven.

### Security

- **`install.sh` no longer writes through a symlinked parent directory (high).**
  The `cp_*` symlink defenses dropped a symlink at the destination _leaf_ file
  but `mkdir -p "$(dirname …)"` still followed a symlinked _parent_ — a repo
  shipping `.githooks -> ~/.ssh` (or any scaffold dir as a symlink) made a
  routine `install.sh` write every scanner/hook/workflow through the link to an
  out-of-repo target, silently overwriting files there with no backup, while the
  in-tree path stayed a symlink so the guardrails never landed (a fail-open
  teammates inherit on clone). A new multi-level `_mkdir_safe` in `install-lib.sh`
  drops any symlink at every path component before `mkdir`; `scripts/dev-setup.sh`
  had this (B4) but the user-facing installer never received it. Regression in
  `tests/cases/09` (dir-symlink plant driving `install.sh`).
- **Two one-commit ways to neuter the secret scanner are closed (high).** The
  orchestrator's deletion guard refused only a full _removal_ of a
  `.forbidden-patterns/*.txt`. Gutting `secrets.txt` to comments-only (present but
  zero patterns) made `check-secrets` treat it as "nothing to scan" and exit 0 at
  both the hook and CI; and `git mv secrets.txt secrets.txt.disabled` was reported
  by git as a rename (R), not a delete (D), so the guard's list was empty. A
  present-but-empty (or all-invalid-regex) config now fails **closed** at both
  gates, and the deletion guard uses `--no-renames` so a rename surfaces as a
  deletion. Regressions in `tests/cases/08`.
- **NUL-injection bypass across all scanners (macOS/BSD).** The shared awk
  line-length cap truncates a record at an embedded NUL on a C-string awk, so
  content _after_ a NUL byte was silently lost — a secret placed after a NUL
  slipped `check-secrets` entirely, and a lone NUL prepended to an agent-read
  `.md` reclassified it as "binary" and dodged the hidden-Unicode (Trojan Source /
  Rules File Backdoor) scan. All four scan pipelines now strip NULs (`tr -d '\000'`)
  before the cap, and the hidden-Unicode binary skip requires a binary _extension_
  in addition to a NUL, so text/agent files are always scanned while images keep
  their false-positive exemption. Regressions in `tests/cases/03` and `06`.
- **`check-patterns` fails closed on over-long lines.** A forbidden pattern on a
  line over `MAX_LINE_LENGTH` was dropped with only a warning and exit 0 — the
  last fail-open in the over-cap sweep. It now reports and rejects like the other
  scanners. Regression in `tests/cases/06` (invoked directly, since `check-secrets`
  masks it end-to-end).
- **`scaffold-allow` now works on a column-0 comment line.** The exemption filter
  ran on `grep -n` output, so its `^` anchor could never match a comment leader at
  the start of a line (the line begins with `NN:`) — the documented start-of-line
  form never exempted. The anchor now tolerates the line-number prefix across all
  five scanners. Regression in `tests/cases/03`.
- **Wider secret coverage; narrower config-dir skip.** Added AWS `ABIA`/`ACCA`
  key-id prefixes, Slack app-level (`xapp-`) and config/refresh (`xoxe-`) tokens,
  and the Stripe webhook signing secret (`whsec_`); lowered the JWT payload-segment
  floor so a compact-claim token (e.g. `{"id":7}`) is no longer missed. Narrowed
  the `check-secrets` scan-skip from all of `.forbidden-patterns/` to only its
  `*.txt` configs, so a committed `.forbidden-patterns/creds.env` is scanned.
  Regressions in `tests/cases/03`.
- **CI supply-chain hardening.** The PHP lint job (consumer template) now runs
  `composer install --no-scripts --no-plugins` (matching the frontend job's
  `--ignore-scripts`) and surfaces an install failure instead of swallowing it;
  the maintainer `actionlint` install downloads the pinned release _asset_ and
  verifies its per-platform sha256 (OS/arch-aware) rather than trusting a mutable
  asset; and the CI linters (`ruff`, `pytest`/`pytest-cov`, `diff-cover`) are
  version-pinned to match the repo's own cooldown posture.

### Added

- **`install.sh --gitleaks-ci`** installs the gitleaks CI workflow
  (`.github/workflows/gitleaks.yml`), symmetric with `--coverage-gate`. Previously
  `--gitleaks-hook` only pointed users at `gitleaks.yml.template`, which `npx`
  users have no on-disk copy of. `uninstall.sh` removes it too. Regression in
  `tests/cases/09`.
- **`RECOMMENDATIONS.md` and `CHANGELOG.md` are now in the npm `files` allowlist.**
  Four installed templates and the README's relative links point at
  `RECOMMENDATIONS.md`, but it (and `CHANGELOG.md`) were absent from the published
  tarball, so `npx` users had dangling links and no copy on disk. The
  `tests/cases/11` bundle guard now fails closed if either drops out.

### Changed

- **`release.yml` documents the npm-publish gating options** (a protected
  `environment` with required reviewers and/or a tag-protection ruleset). Left
  opt-in — it needs out-of-band GitHub/npm configuration — so a fresh clone's
  tokenless release pipeline keeps working.

### Documented

- README drift corrected: the "adopting on an existing codebase" section now
  states CI scopes size/pattern/hygiene to the diff (only secret/filename scans
  are whole-tree); agent-runtime hooks are described as a shipped opt-in layer
  (`--claude`/`--cursor`), not "deferred"; the `npx` upgrade path documents
  `@latest`; the hygiene override ids include `hidden-unicode`; the per-line
  escape valve names the four comment leaders; and uninstall is documented per
  install channel. `forbidden-patterns/README.md` now states `secrets.txt` scans
  every staged blob regardless of extension.

### Tests

- Coverage added for eight previously-unpinned guardrail branches: the
  `commit-msg` auto-generated-subject exemptions (`Revert`/`fixup!`/`squash!`/
  `Reapply`) and `feat!:` marker, the `check-size` `severity = "warn"` downgrade,
  the `MAX_LINES` override's reject reason, the mid-file BOM / plain bidi /
  tag-block hidden-Unicode arms, the diff3 `|||||||` conflict marker, and the
  `eslint` / `php -l` pre-commit linter blocks.

## [v0.10.0] — 2026-07-01

A packaging / robustness release that closes the remaining findings of the
2026-06-30 packaging audit (B1–B12). Two scanner-coverage additions
(`check-filenames` now blocks non-dotfile `*.env` files and binary
key/keystore files), native-Windows / Git-Bash `npm` install support, and a
set of `install.sh` / `dev-setup.sh` robustness and parity fixes.

### Security

- **`check-hygiene` fails closed on over-long lines (B2, high).** The A1
  fail-closed fix had only reached `check-secrets`/`check-patterns`; the
  conflict-marker and hidden-Unicode (Trojan Source / CVE-2021-42574 / Rules
  File Backdoor) branches still dropped any line over `MAX_LINE_LENGTH` (50k)
  silently and exited 0, so a bidi override or zero-width char on a minified /
  base64 blob rode straight through the scaffold's named defense. Both branches
  now report the unscannable line and reject the commit, at the rule's
  configured severity (a repo that downgraded the rule to `warn` still gets a
  warn, not a hard block). Regressions in `tests/cases/06` (#45g, #45h).
- **`agent-precheck` fails closed on over-long lines (B6, medium).** The
  agent-write PreToolUse hook dropped any line over `MAX_LINE_LENGTH` and then
  exited 0 (allow), so a secret or a `curl|bash` padded past the cap was silently
  permitted at write time while its short form blocked at exit 2. An unscannable
  over-cap line now BLOCKS (exit 2) with an actionable message — the one place
  this advisory hook fails closed rather than open, since an unscannable line is
  not the same as a missing scanner. Regression in `tests/cases/07` (#48h). This
  completes the over-cap fail-closed sweep across all four scanners
  (check-secrets/check-patterns/check-hygiene/agent-precheck).
- **`check-filenames` now blocks non-dotfile env files (B5, medium).** The env
  arm matched only `.env`/`.env.*`, so `config.env`/`prod.env`/`staging.env` — which
  end in `.env` without starting with it — committed clean; paired with an unquoted
  `KEY=value` secret they also slipped the (deliberately deferred) quoted-only content
  scanner, a dual-layer leak. The arm is now `.env|.env.*|*.env`; `*.env.example`-style
  templates end in `.example`, so the `.env.example` allowlist is unaffected. Regressions
  in `tests/cases/04` (#36e/#36f block `config.env`/`prod.env`/`PROD.ENV`; #36g keeps
  `config.env.example` passing).
- **`check-filenames` now blocks binary key/keystore files (B7, low).** The
  filename block knew only `*.pem`, `.env*`, and the four `id_*` SSH names, so a
  committed `server.key` / `cert.p12` / `id.pfx` / `store.jks` / `key.ppk` passed —
  and because these are binary blobs with no PEM `-----BEGIN … PRIVATE KEY-----`
  armor, the content scanner can't backstop them, so both layers failed open. A new
  `*.key|*.p12|*.pfx|*.jks|*.ppk` arm now blocks them (fail-closed; the filename is
  the only signal). `*.key` also catches the common TLS/Kubernetes spelling; the rare
  Keynote `.key` bundle is a deliberate false-positive trade-off (rename / keep out of
  git). Regressions in `tests/cases/04` (#36h/#36i block all five extensions +
  case-folded `SERVER.KEY`; #36j keeps public-key `authorized_keys` passing).
- **npm package now ships the gitleaks + dependency-review CI templates (B3).**
  `gitleaks.yml.template` and `dependency-review.yml.template` were git-tracked
  and documented ("copy it in" in the README / `install.sh`) but missing from
  the `package.json` `files` allowlist, so `npx` / `npm` consumers silently
  lacked two security-CI gates that git-clone and Homebrew users get. Both are
  now bundled, and the `tests/cases/11` bundle-drift guard globs every
  `.github/workflows/*.yml.template` so it fails closed on any future
  documented-but-unbundled workflow — the guard previously derived its required
  set only from files `install.sh` reads, making manual-copy templates invisible.
- **`scripts/dev-setup.sh` no longer writes through a symlink (B4).** The
  maintainer dogfooding script rendered templates with bare `cp` / `mkdir -p`,
  so a leftover or planted symlink in the gitignored `.githooks/` /
  `.forbidden-patterns/` dirs could redirect a rendered scanner (or the whole
  `lib/` dir) to a target outside the repo — the A7 write-through class that
  `install.sh` already defends. It now drops any symlink at a rendered file or
  directory before writing, so renders always land as real files in-tree.
  Regressions in `tests/cases/09` (file-symlink + dir-symlink plants).
- **`scripts/dev-setup.sh` guards the `core.hooksPath` wiring like `install.sh`
  (B9, B10, low).** The wiring step ran `git config core.hooksPath .githooks`
  unconditionally, so (B9) run before `git init` it aborted with a raw `fatal:
not in a git directory` (exit 128) _after_ every file was already rendered, and
  (B10) it silently clobbered a pre-existing `core.hooksPath` (e.g. a Husky /
  lefthook setup). It now mirrors `install.sh`: a `git rev-parse --git-dir` guard
  warns and continues (exit 0) outside a git repo, and an existing non-`.githooks`
  hooks path is preserved with a warning instead of overwritten. The summary line
  reports the real outcome. Regressions in `tests/cases/09` (Husky path survives;
  unset → `.githooks`; no-`git init` clone warns + exits 0).
- **npm package no longer blocks native-Windows / Git-Bash installs (B8, low).**
  `package.json` carried `os: ["darwin","linux"]`, which npm enforces as a hard
  `EBADPLATFORM` — native Windows (Git Bash and PowerShell) reports `win32`, so the
  install was refused outright, _before_ `cli.js` could print its "run it from Git
  Bash or WSL" hint, and in contradiction of the README's Windows support. The `os`
  field is dropped; the runtime already degrades gracefully when `bash` is absent.
  Guarded in `tests/cases/11` (a jq check that `package.json` has no `os` field, or
  one that permits `win32`).
- **`install.sh` no longer aborts mid-run when one file's backup slots are full
  (B12, low).** When all 100 `.scaffold-bak[.N]` slots for a `--force`-replaced file
  were taken, `_backup` returned non-zero and the bare caller aborted the whole
  script under `set -e` — leaving hooks unwired, before `core.hooksPath` was set,
  with no summary. The three call sites now skip that one file (leaving the user's
  version untouched — no backup means no safe overwrite) and the install continues
  and completes. `_backup` prints a "skipping this one file — re-run after cleanup"
  notice so the skip is visible. Guarded in `tests/cases/12` (100 saturated slots →
  the file keeps its local edit and the run still reaches `Done`).
- **`RELEASING.md` release-notes extraction no longer risks a blank or leaky
  GitHub Release (B11, low).** The `awk` that slices the CHANGELOG section for a tag
  used an unanchored end-of-section guard (`!/vX\.Y\.Z/`), so an adjacent heading
  containing the version as a substring (e.g. `vX.Y.Z-hotfix`) could leak its body
  into the notes; and if the maintainer ran the snippet without substituting
  `vX.Y.Z`, it emitted 0 bytes and `gh release create` shipped an empty-body Release
  with no error. The guard is now anchored (`!/^## \[vX\.Y\.Z\]/`) and a
  `[ -s /tmp/notes.md ]` check aborts loudly on empty notes before publishing.
  Docs-only (maintainer procedure); both cases were reproduced and the fix verified
  against a crafted CHANGELOG fixture.

### Changed

- **`install.sh` file-write helpers extracted to a sourced `install-lib.sh`.**
  Internal refactor, no behavior change: the `cp_scaffold`/`cp_safe`/`cp_pattern`
  policy functions and the shared `_cp_replace`/`_backup`/`mkx` mechanism (~130
  lines) moved into `install-lib.sh`, which `install.sh` now sources, dropping it
  from 500 → 380 lines (back under the scaffold's own 500-line module cap). The
  new file is shipped in the npm bundle (`package.json` `files`) and covered by the
  bundle-completeness and shellcheck gates. Verified by the full suite plus an
  end-to-end install smoke test.

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
  - `tests/lib/common.sh` (shared helpers/bootstrap) + nine `tests/cases/*.sh`,
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
  `CLAUDE.md` is now _merged_ — a marked `@AGENTS.md` import block is appended
  once if missing, and existing content is never replaced, even with `--force`
  (previously `--force` overwrote it wholesale with the pointer stub,
  destroying hand-written project memory). An existing `AGENTS.md` is likewise
  left untouched (its Project section is user-authored). For every other file,
  `--force` now backs the current copy up to `<file>.scaffold-bak` before
  replacing it, so no edit is silently destroyed. `uninstall.sh` strips only
  the marked block from a user's `CLAUDE.md` (or removes the file only when
  it's an unmodified scaffold-created pointer). +5 tests.

## [v0.7.0] — 2026-06-16

Toolchain setup: the scaffold now ships the tool _configs_ its enforcement
already assumed (strict `tsconfig.json`, Prettier, Vitest, pytest+coverage),
detects and offers to install the _binaries_ (safe auto-run only on an
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
  _execution_ of changed lines, not assertion quality — documented ceiling, with
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
  _prose-only_ rule (`AGENTS.md` git discipline + `coding-rules.md` rule 9 + the
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
  CPython 3.12 deprecated `utcfromtimestamp()` in the _same_ change as
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
  option _value_, not syntax, so no `eslint` rule catches it. +3 fixtures
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
  deliberately not enabled — flagging every naive `datetime` is timezone _policy_
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
  (`git show :0:<path>`), not `wc -l`; the secret scan covers _every_ tracked
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
  assigned and the repo is checked out, so GitHub rejected the _entire_
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
  - _Integration tests hit a real database, not mocks._ Mocked tests
    pass against the mock, not the schema; migration drift hides.
  - _Tests cover every code path; back claims with measurement._
    "We have tests" ≠ "this is tested." Numbers from real runs beat
    narrative correctness.
  - _No silent failures._ When work fails, log WARN+ AND surface in
    response. Catch-and-return-success is the most expensive habit
    in production code.
  - _Hold shared-resource locks for contiguous work, not per
    operation._ Per-op locking causes thrash + starvation under
    contention (GPU, DB pool, hardware port).
  - _Never print, cat, or echo secret files._ AI agents' habit of
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
