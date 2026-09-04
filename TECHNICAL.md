# Technical reference

Deep reference detail for [ai-coding-rules-scaffold](./README.md): every rule the tooling enforces, the philosophy behind the design, the full per-stack coverage matrix, the file-by-file inventory of what an install writes into your project, per-project customization and rule overrides, the opt-in layers, how to verify the guardrails are actually armed, and update/uninstall instructions.

Start with [README.md](./README.md) for what the scaffold does and how to install it; come back here for the rest.

## Philosophy

**Short doc rule list humans remember + full tool enforcement for the rest.** If the build breaks on `ruff C901`, the fix is forced — no one needs to remember that nested-if depth matters.

The file-size rule (max 500 lines) is the one rule to never raise. Every other rule has tradeoffs in specific cases; unbounded file growth is how projects rot.

Enforcement runs in two places, sharing the same scripts:

- **Pre-commit hook** — blocks the commit locally, scanning only your **staged** files. Fast feedback, skippable with `--no-verify`.
- **CI workflow** — blocks the PR server-side. Unskippable.

Both invoke the same `lib/check-*` scripts (`check-size`, `check-large-files`, `check-patterns`, `check-filenames`, `check-secrets`, `check-hygiene`). The hook and CI can't drift apart because there's nothing to keep in sync, they call the same code. What differs is _scope_. The hook scans your staged files; CI scopes its **quality gates** (ruff, eslint/prettier, and the size / forbidden-pattern / hygiene guardrails) to the **PR/push diff** via the shared `.githooks/lib/ci-changed-files` helper, so installing onto an existing repo doesn't retroactively fail pre-existing code. The **secret and credential-filename scans stay whole-tree** in CI, the non-overridable security boundary, where catching an already-committed key is the whole point. Same scripts everywhere: scoped to the diff for quality gates, whole-tree for secrets. Each script is also runnable on its own. It reads a **NUL-separated** file list on stdin, not newline-separated (`git ls-files -z | .githooks/lib/check-secrets`; a plain `git ls-files |` pipe scans nothing, silently), so you can wire it into Husky, lefthook, or any other orchestrator without rewriting the logic.

## Supported stacks

Two always-on enforcement layers (pre-commit hook + CI mirror) plus optional agent-runtime hooks. What each stack gets:

- **Python** — `ruff` (annotations, complexity, `pathlib`, no-blind-except, async-safety `ASYNC`, FastAPI `FAST`, logging `G`/`LOG`, a curated `flake8-bandit` security subset) **+** a `backend.txt` regex deny-list: `print()`, `breakpoint()`/`pdb`/`ipdb`, `os.path.join`, deprecated `datetime.utcnow()` / `utcfromtimestamp()`. FastAPI (Pydantic responses) and SQLAlchemy-2.0 conventions live in `coding-rules.md`.
- **TypeScript / JavaScript** — type-aware `eslint` (`strictTypeChecked`: floating/misused promises, `switch-exhaustiveness-check`, `preserve-caught-error`, `no-explicit-any`, import sort + unused-import removal) **+** `tsc --noEmit` (against a shipped strict `tsconfig.json`) **+** `prettier --check` (formatting, run separately from eslint) **+** a `frontend.txt` deny-list: `console.log`/`debugger`/`alert`, focused tests (`.only`), `@ts-ignore`/`@ts-nocheck`, hardcoded `localhost`, and TLS-verification-disable (`NODE_TLS_REJECT_UNAUTHORIZED`, `rejectUnauthorized: false`).
  - **React** — `dangerouslySetInnerHTML` (XSS); opt-in `react-hooks` + `jsx-a11y` blocks.
  - **Vue** — `.vue` scanned; `v-html` (XSS).
  - **Svelte** — `.svelte` scanned; `{@html}` (XSS).
- **Testing** — a runner config ships per stack (`vitest.config.ts` for TS/JS unless the project already uses Jest; `pytest.ini` + `.coveragerc` for Python), and `install.sh` installs `.github/workflows/tests.yml` by **default** so pytest/vitest actually run on every PR/push, no coverage threshold. On top of that, the **opt-in patch-coverage gate** (`--coverage-gate`) swaps `tests.yml` for `coverage.yml`, which runs the same tests and additionally fails a PR when _changed_ lines ship untested. It gates execution of changed lines, not assertion quality: see [`RECOMMENDATIONS.md`](./RECOMMENDATIONS.md) on why you can't fully machine-force meaningful tests. `--no-test-workflow` opts out of installing either (a loud, recorded skip) for a repo that genuinely cannot run tests in CI.
- **PHP** — `php -l` syntax + `phpcs` (when configured) **+** `php.txt`: `var_dump`/`print_r`, `->dd()`/`dump()`, `die`/`exit` (opt-in).
- **Go** — `go.txt`: `fmt.Println`/`Printf` debug, `panic`/`print` (opt-in); ready-to-uncomment golangci-lint CI job.
- **Rust** — `rust.txt`: `dbg!`, `println!`, `.unwrap()`/`.expect()` (opt-in); clippy CI job stub.
- **Java / Kotlin** — `java.txt` / `kotlin.txt`: `System.out.println`, `println`, `printStackTrace`; setup-java/Gradle CI stubs.
- **Ruby** — `ruby.txt`: `binding.pry`, `puts` (opt-in); setup-ruby CI stub.
- **Shell** (`*.sh`/`*.bash`) — `shell.txt`: `curl | bash`, `rm -rf /`, `chmod 777`, `git --no-verify` (hook-bypass). `shell.txt` and `secrets.txt` ship in **every** mode, so a Python or frontend project with shell scripts gets shell-pattern coverage too; `install.sh --shell` (or the manifest-less auto-detect fallback) is for projects that are _only_ shell, with no Python/TS toolchain configs to install.
- **Every language / all files**, `secrets.txt` token shapes (AWS `AKIA`/Bedrock, GCP, GitHub, GitLab PAT + runner/deploy/agent tokens, Slack, OpenAI/Anthropic, Stripe, Supabase, OpenRouter, HuggingFace, structural JWTs, private keys, URL-embedded creds), credential-file blocking (`.env`, `*.pem`, SSH keys), the 500-line file-size cap, the 500 KB large-binary cap (`check-large-files`), merge-conflict markers, case-only filename collisions, and hidden-Unicode (Trojan-Source) scanning.

Language pattern files auto-install when their manifest is detected (`go.mod`, `Cargo.toml`, `composer.json`, `pom.xml`/`build.gradle`, `Gemfile`), or install them all with `--all-langs`. Anything not listed still gets the always-on cross-language layers (secrets, file size, filenames, hygiene). Adding a new language is just dropping a `.forbidden-patterns/<lang>.txt` with a `# scaffold-extensions:` header — no script changes.

## What lands in your project

| Scaffold file                                                                       | Installed as                                                                | Purpose                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ----------------------------------------------------------------------------------- | --------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AGENTS.md.template`                                                                | `AGENTS.md`                                                                 | Primary agent doc: git discipline + project section                                                                                                                                                                                                                                                                                                                                                                                          |
| `CLAUDE.md.pointer`                                                                 | `CLAUDE.md`                                                                 | Pointer importing `AGENTS.md` + `coding-rules.md` into Claude Code's context                                                                                                                                                                                                                                                                                                                                                                 |
| `coding-rules.md`                                                                   | `coding-rules.md`                                                           | Short list of code-level rules that aren't tool-enforceable                                                                                                                                                                                                                                                                                                                                                                                  |
| `operational-rules.md`                                                              | `operational-rules.md`                                                      | Process and collaboration rules — failure modes that no linter can catch                                                                                                                                                                                                                                                                                                                                                                     |
| `ruff.toml.template`                                                                | `ruff.toml`                                                                 | Python lint config                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `pytest.ini.template`                                                               | `pytest.ini`                                                                | Python test-runner config (skipped if pyproject/tox already configures pytest — including in a subdirectory, since a root `pytest.ini` would shadow it)                                                                                                                                                                                                                                                                                      |
| `.coveragerc.template`                                                              | `.coveragerc`                                                               | coverage.py config for the patch-coverage gate                                                                                                                                                                                                                                                                                                                                                                                               |
| `eslint.config.js.template`                                                         | `eslint.config.js`                                                          | TS/JS lint config (flat config, ESLint 9+)                                                                                                                                                                                                                                                                                                                                                                                                   |
| `tsconfig.json.template`                                                            | `tsconfig.json`                                                             | Strict TS config the type-aware eslint rules + `tsc --noEmit` assume                                                                                                                                                                                                                                                                                                                                                                         |
| `.prettierrc.json.template`                                                         | `.prettierrc.json`                                                          | Prettier formatting config (runs separately from eslint)                                                                                                                                                                                                                                                                                                                                                                                     |
| `.prettierignore.template`                                                          | `.prettierignore`                                                           | Paths Prettier should not format                                                                                                                                                                                                                                                                                                                                                                                                             |
| `vitest.config.ts.template`                                                         | `vitest.config.ts`                                                          | Vitest runner + V8 coverage config (skipped if the project uses Jest)                                                                                                                                                                                                                                                                                                                                                                        |
| `githooks/pre-commit.template`                                                      | `.githooks/pre-commit`                                                      | Hook orchestrator, invokes the six `lib/check-*` scripts below unconditionally, plus `check-gitleaks` when `--gitleaks-hook` is installed                                                                                                                                                                                                                                                                                                    |
| `githooks/lib/check-{size,large-files,patterns,filenames,secrets,hygiene}.template` | `.githooks/lib/check-{size,large-files,patterns,filenames,secrets,hygiene}` | Reusable check scripts; the same scripts run from CI so hook and CI can't drift                                                                                                                                                                                                                                                                                                                                                              |
| `githooks/lib/scaffold-config.template`                                             | `.githooks/lib/scaffold-config`                                             | Reads per-project rule overrides from `.scaffold.toml` (per-path size caps, per-rule disable / severity)                                                                                                                                                                                                                                                                                                                                     |
| `githooks/lib/scaffold-audit.template`                                              | `.githooks/lib/scaffold-audit`                                              | Lists every active override in `.scaffold.toml`; run locally and echoed by CI                                                                                                                                                                                                                                                                                                                                                                |
| `githooks/local.d/README.md.template`                                               | `.githooks/local.d/README.md`                                               | Documents the project-local check contract. The **directory** is yours: drop executables in and hook + CI both run them, and `install.sh` never writes into it                                                                                                                                                                                                                                                                               |
| `.scaffold.toml.template`                                                           | `.scaffold.toml`                                                            | Per-project rule overrides — ships empty (commented), enforces nothing until edited                                                                                                                                                                                                                                                                                                                                                          |
| `.github/workflows/lint.yml.template`                                               | `.github/workflows/lint.yml`                                                | CI mirror — invokes the same `lib/check-*` scripts as the hook, scoped to the PR/push diff (`lib/ci-changed-files`) for quality gates, whole-tree for the secret/credential scans                                                                                                                                                                                                                                                            |
| `.github/workflows/tests.yml.template`                                              | `.github/workflows/tests.yml`                                               | Default-on test execution: runs pytest/vitest on every PR/push, no coverage threshold. Skipped by `--no-test-workflow`; replaced by `coverage.yml` under `--coverage-gate`                                                                                                                                                                                                                                                                   |
| `githooks/lib/ci-changed-files.template`                                            | `.githooks/lib/ci-changed-files`                                            | Resolves the PR/push diff so CI quality gates scan only changed files; fails open to the whole tree when there's no diff base                                                                                                                                                                                                                                                                                                                |
| `.github/dependabot.yml.template`                                                   | `.github/dependabot.yml`                                                    | Weekly grouped version bumps for the SHA-pinned GitHub Actions                                                                                                                                                                                                                                                                                                                                                                               |
| `forbidden-patterns/backend.txt.template`                                           | `.forbidden-patterns/backend.txt`                                           | Python patterns consumed by hook + CI                                                                                                                                                                                                                                                                                                                                                                                                        |
| `forbidden-patterns/frontend.txt.template`                                          | `.forbidden-patterns/frontend.txt`                                          | TS/JS patterns consumed by hook + CI                                                                                                                                                                                                                                                                                                                                                                                                         |
| `forbidden-patterns/secrets.txt.template`                                           | `.forbidden-patterns/secrets.txt`                                           | Secret/credential patterns, scanned across all file types                                                                                                                                                                                                                                                                                                                                                                                    |
| `forbidden-patterns/shell.txt.template`                                             | `.forbidden-patterns/shell.txt`                                             | Dangerous shell patterns (`curl \| bash`, `rm -rf /`, `chmod 777`) for `*.sh` and `*.bash`                                                                                                                                                                                                                                                                                                                                                   |
| _generated by `install.sh`, no template_                                            | `.githooks/.scaffold-manifest`                                              | Provenance record (`<sha256> <scaffold version> <path>`, one line per file the installer wrote). Lets a later upgrade tell "unchanged since we wrote it" (refresh) apart from "you edited this" (keep, and say so). **Commit it.** Delete it and every drift-preserving file falls back to comparing against today's template, which is what looked like a hand-edit before this file existed. See [Update & uninstall](#update--uninstall). |
| _generated by `install.sh`, no template_                                            | `.gitignore` (rules appended; file created if missing)                      | Adds `*.scaffold-bak`, `*.scaffold-bak.*`, `.githooks/.scaffold-manifest.new.*` and `.githooks/.scaffold-manifest.tmp.*` so upgrade backups never get swept into a commit. Written before any other file, on every run, including one that goes on to refuse a write (for example a symlinked `.githooks`/`.github`/`.claude`/`.cursor` and exit non-zero): this edit lands even when the rest of the install does not.                      |

Scripts (stay in the scaffold repo):

| Script               | Purpose                                                                                                                                |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `install.sh`         | Copy templates into your project, wire `core.hooksPath`, detect/offer the toolchain                                                    |
| `uninstall.sh`       | Remove unmodified scaffold files, unwire the hook                                                                                      |
| `scaffold-doctor.sh` | Check whether an installed project's guardrails are armed, not just present — see [Check whether it's armed](#check-whether-its-armed) |

## What the tooling enforces

The pre-commit hook now invokes `ruff` / `eslint` against staged files
when their configs are present and the tool is on PATH — plus, for
TypeScript, `tsc --noEmit` (against the shipped strict `tsconfig.json`) and
`prettier --check` when a prettier config is present — so most of the
build-breaking rules below also fire at commit time, not only in CI.
Linters, the type-checker, and the formatter are silently skipped if not
installed; CI is the authoritative backstop.

The shipped `eslint.config.js` extends typescript-eslint's
**`strictTypeChecked`** tier (type-aware linting), wires import sorting and
unused-import removal as parity with `ruff`'s `I` / `F401`, and ships an
opt-in `react-hooks` block — comparable to what create-t3-app / antfu's
config give a TypeScript project out of the box. Run `npx eslint --inspect-config`
to see the resolved rule set.

Build-breaking (`ruff` / `eslint`, on every lint + commit + in CI):

| Concern                                                                                     | Rule                                                                                        |
| ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Nested control flow > 3 deep                                                                | `ruff C901`, `eslint max-depth: 3`                                                          |
| Cyclomatic complexity > 10                                                                  | `ruff C901`, `eslint complexity: 10`                                                        |
| `os.path.join` / string path math                                                           | `ruff PTH100-208`                                                                           |
| Blind `except Exception: pass`                                                              | `ruff BLE001`                                                                               |
| Missing public-API return types                                                             | `ruff ANN201`                                                                               |
| Function size > 80 statements (Python) / 80 lines (TS/JS)                                   | `ruff PLR0915` (`max-statements`), `eslint max-lines-per-function`                          |
| Too many branches in a function                                                             | `ruff PLR0912` (`max-branches`)                                                             |
| Blocking HTTP/file/subprocess call inside `async def`                                       | `ruff ASYNC210-230`                                                                         |
| Non-`Annotated` FastAPI dependency / unused path param                                      | `ruff FAST002`, `FAST003`                                                                   |
| f-string / `%` / `.format()` in a logging call; `.warn()` / root logger                     | `ruff G002 G004 G010 LOG`                                                                   |
| `shell=True` / `eval` / unsafe deserialization (`pickle`) / weak hash                       | `ruff S` (curated flake8-bandit subset)                                                     |
| Line length > 100                                                                           | `ruff E501`                                                                                 |
| Unsorted / unused imports                                                                   | `ruff I`, `F401`; `eslint import-x/order`, `unused-imports/no-unused-imports`               |
| `any` in TypeScript without comment                                                         | `@typescript-eslint/no-explicit-any`                                                        |
| Floating / misused promises (TS)                                                            | `@typescript-eslint/no-floating-promises`, `no-misused-promises` (type-aware)               |
| Non-exhaustive `switch` over a union/enum (missing member)                                  | `@typescript-eslint/switch-exhaustiveness-check` (type-aware)                               |
| Re-throwing in `catch` while discarding the original error cause/stack                      | `eslint preserve-caught-error` (needs ESLint ≥ 9.35)                                        |
| TypeScript type errors                                                                      | `tsc --noEmit` (hook + CI, when `tsconfig.json` present)                                    |
| Unformatted TS/JS                                                                           | `prettier --check` (hook + CI, when a prettier config is present; `prettier --write` fixes) |
| Changed lines shipped without a test (opt-in strictness layer on default-on test execution) | `diff-cover` patch-coverage gate (`--coverage-gate`, CI)                                    |

Commit + CI-breaking (pre-commit hook + `lint.yml`):

| Concern                                                                                                                                                                                                                                                                                                               | Check                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `print()`, `breakpoint()`, `pdb`/`ipdb.set_trace()`, `os.path.join`, deprecated `datetime.utcnow()`/`utcfromtimestamp()` in Python files                                                                                                                                                                              | regex (backend.txt)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `console.log` / `debugger` / `alert` in TS/JS                                                                                                                                                                                                                                                                         | regex (frontend.txt)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| XSS sinks — `dangerouslySetInnerHTML` (React), `v-html` (Vue, `.vue`), `{@html}` (Svelte, `.svelte`)                                                                                                                                                                                                                  | regex (frontend.txt)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Focused tests (`.only`), `@ts-ignore` / `@ts-nocheck`, hardcoded `localhost`/`127.0.0.1` URLs, TLS-verification-disable (`NODE_TLS_REJECT_UNAUTHORIZED`, `rejectUnauthorized: false`)                                                                                                                                 | regex (frontend.txt)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Dangerous shell in `*.sh`/`*.bash` — `curl \| bash`, `rm -rf /`, `chmod 777`, `git --no-verify` (hook bypass)                                                                                                                                                                                                         | regex (shell.txt)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| File size > 500 lines                                                                                                                                                                                                                                                                                                 | line count of the staged blob (`git show :0:<path>`, counting a final line with no trailing newline)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Large binary file > 500 KB (`check-large-files`, P-15)                                                                                                                                                                                                                                                                | byte size of the staged blob (`git cat-file -s :0:<path>`); default cap raisable via `.scaffold.toml [large-files] default = <bytes>`. No extension skip list, unlike `check-size`, so a video, model checkpoint, database dump, or zipped export is caught even though it would pass the line-count cap untouched                                                                                                                                                                                                                                                                                                                             |
| TODO/FIXME without ticket ref                                                                                                                                                                                                                                                                                         | regex (opt-in; commented in template)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| Secret / credential leaks (AWS `AKIA`/Bedrock, GitHub/GitLab tokens, Stripe, Supabase, OpenRouter, OpenAI/Anthropic, structural JWTs, private keys, URLs with embedded credentials, quoted hardcoded `password`/`token`/`api_key` assignments — unquoted/env-var forms are better caught by the gitleaks layer below) | regex (case-insensitive for keyword rules; token-shaped rules are case-sensitive via a `(?-i)` marker, so an all-hex prefix like AWS `ACCA` cannot collide with a SHA-256 digest). Scans **every** tracked file's staged blob as text (no extension allowlist, so renaming a payload can't skip it); NUL bytes are stripped so they can't hide content. A single line longer than `MAX_LINE_LENGTH` (50000) is dropped before the regex (so a minified/binary blob can't hang the scan) and the file is then **rejected as unscannable** (fail-closed) — split/relocate the asset, raise `MAX_LINE_LENGTH`, or point a dedicated scanner at it |
| Committed `.env` / `*.pem` / SSH private keys (`id_rsa`, `id_ed25519`, `id_ecdsa`, `id_dsa`)                                                                                                                                                                                                                          | filename check (`.env.example` / `.env.sample` / `.env.template` allowed)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Merge-conflict markers (`<<<<<<<` / `\|\|\|\|\|\|\|` / `>>>>>>>`) left in a file                                                                                                                                                                                                                                      | `check-hygiene` (staged-blob scan)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Case-only filename collisions (`Readme.md` vs `README.md`) that break macOS/Windows checkouts                                                                                                                                                                                                                         | `check-hygiene` (path scan; diff-scoped in CI like the other quality gates)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| Hidden Unicode — bidi controls (Trojan Source), zero-width, tag block — in a staged text file                                                                                                                                                                                                                         | `check-hygiene` (LC_ALL=C byte scan; leading BOM allowed, binary skipped)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |

### Per-line escape valve

When a regex match is intentional — a CLI entry point that needs `print`,
a docs example showing an AWS key prefix, a fixture with a synthetic
credential — append `scaffold-allow` (any case) after a comment leader
(`#`, `//`, `/*`, or `<!--`) on the matched line. The marker must follow
a comment leader; a bare `scaffold-allow` inside a string literal is NOT
exempt. `check-patterns` and `check-secrets` skip lines containing the
marker; `check-filenames`, `check-size`, and `check-large-files` are file-level
and unaffected. See `forbidden-patterns/README.md` for examples and the full
leader spec.

**Reviewers: every PR that adds or moves a `scaffold-allow` marker is
suppressing a guardrail.** Treat new markers like new `# noqa`s — confirm
the suppression is justified before approving. Audit the full set with
`git grep -i scaffold-allow`.

### Per-project rule overrides (`.scaffold.toml`)

`scaffold-allow` exempts a single _line_. When a team disagrees with a rule
_as a whole_ — or needs a bigger size budget for a legacy tree — record that
decision once, durably and auditably, in a repo-root `.scaffold.toml`. It
ships empty (all examples commented), so it changes nothing until you edit it.

```toml
[size]
default     = 800          # raise the project-wide line cap (default 500)
"legacy/**" = 2000         # most-specific matching glob wins

[rules."php/Remove var_dump() before committing - dumps to stdout"]
disabled = true            # turn a forbidden-pattern rule off entirely
reason   = "legacy reporting module, JIRA-1234"
by       = "alex 2026-06-11"

[rules."frontend/Use the project logger, not console.log"]
severity = "warn"          # error (default) → warn: still reported, doesn't fail

[rules.case-collision]     # hygiene ids: conflict-marker, case-collision, hidden-unicode
severity = "warn"
```

- **Rule ids.** Forbidden-pattern rules are keyed `"<patternfile-stem>/<description>"`
  (the text after the TAB in `.forbidden-patterns/<lang>.txt`). Hygiene rules
  use `conflict-marker` / `case-collision` / `hidden-unicode`; the size cap uses
  `size`; the large-file byte cap uses `large-files`.
- **Disable vs downgrade.** `disabled = true` turns the rule off; `severity =
"warn"` keeps emitting the finding (a CI `::warning::`) without failing the
  build — a relaxed rule stays visible, never silent.
- **Modifying a pattern's regex/description** is just editing the
  `.forbidden-patterns/<lang>.txt` you already own; git history is the audit
  trail. `.scaffold.toml` owns disable + severity, so a regex never lives in two
  places.
- **What you cannot override.** The secret scanner and the credential-filename
  check (`check-secrets` / `check-filenames`) ignore `.scaffold.toml` entirely
  — secret/key-file blocking is non-negotiable and can't be turned off
  per-project.
- **Audit.** `.githooks/lib/scaffold-audit` lists every active override; the CI
  guardrails job prints it into the build log. Treat changes to `.scaffold.toml`
  as security-relevant in review, the same as edits to `.githooks/**`.

## Default-on test execution

`install.sh` installs `.github/workflows/tests.yml` by default (#97): a pytest
job and a vitest job, each gated on the matching stack actually being present
(a pytest job on a repo with no `pyproject.toml`/`pytest.ini`/`setup.py`, or a
vitest job where `package.json` never declares `vitest`, no-ops with a logged
reason instead of failing). No coverage threshold: the point is only that
tests actually **run** on every PR/push, closing the gap where a default
install produced lint-only CI and a green check meant "nothing is malformed",
never "nothing is broken." The pytest job installs the project itself first,
but only when it looks actually installable (a `[project]` table or a
`setup.py`, not a pyproject.toml that only holds tool config): `pip install
-e ".[dev]"` when a `dev` extra is declared, else `pip install -e .`, plus
any of `requirements.txt`, `requirements-dev.txt`, or `requirements/dev.txt`
that exist, so tests that import the package under test can actually
collect.

`.github/workflows/tests.yml` is a scaffold-claimed filename, but unlike the
pre-commit hook and `lib/check-*` scanners it is drift-preserving, not
refreshed on re-run (`cp_scaffold_preserve`, #110, the same policy `lint.yml`
got in #105): a project that already has its own hand-written `tests.yml`, or
one it edited after a scaffold install, keeps it, with a `note (drift):` line
explaining how to merge or replace it. `install.sh --force` replaces it
anyway, backed up to `.scaffold-bak` first.

Two ways to change this:

- **`install.sh --coverage-gate`** swaps `tests.yml` for `coverage.yml`:
  same tests, plus a patch-coverage gate on top (see below). Installing both
  would run the suite twice for the same push/PR, so it's always one or the
  other, never both; an upgrade that adds `--coverage-gate` on top of a prior
  default install retires the now-redundant `tests.yml` if it's still
  untouched since install.
- **`install.sh --no-test-workflow`** installs neither. For a repo that
  genuinely cannot run tests in CI. The installer prints a loud recorded skip
  when this flag is used, and its end-of-run summary always states plainly
  which of the three states (`tests.yml`, `coverage.yml`, or no test
  execution at all) the repo ended up in.

## Opt-in layers

Beyond the always-on hook + CI mirror and the default-on test workflow above,
further extras are available. They're off by default so the scaffold stays
minimal; turn them on per project.

- **Agent-runtime guardrails (`install.sh --claude`).** The opt-in third layer —
  catching bad input _before_ the agent writes it, not at commit time.
  Installs a `.claude/settings.json` that denies the agent reading credential
  files (`.env`, `*.pem`, `*.key`, `~/.ssh/**`, `~/.aws/**`, …) and a
  `PreToolUse` hook (`.githooks/lib/agent-precheck`) that scans Write/Edit/Bash
  content against the _same_ `.forbidden-patterns/secrets.txt` the commit-time
  scanner uses — one rule set across agent → commit → CI. Needs `jq` (fails open
  without it). See [`RECOMMENDATIONS.md`](./RECOMMENDATIONS.md).

- **Cursor agent guardrails (`install.sh --cursor`).** The same `agent-precheck`
  wired to two Cursor hooks via `.cursor/hooks.json`: `beforeShellExecution`,
  so a `curl | bash` / `rm -rf /` / `chmod 777` the agent is about to run is
  scanned against `.forbidden-patterns/shell.txt` and blocked (exit 2 = Cursor
  deny); and `beforeReadFile`, so a read of a credential file (`.env`,
  `*.pem`, `~/.ssh/**`, `~/.aws/**`, …) is scanned against
  `.githooks/lib/credential-read-patterns.txt` and denied via a
  `{"permission":"deny"}` JSON response (`beforeReadFile` has no exit-code
  contract, unlike `beforeShellExecution`) — the Cursor sibling of Claude's
  native `permissions.deny` credential-file list. Cursor has no hook that can
  block a write (`afterFileEdit` fires only after the edit has landed), so
  unlike `--claude` the secret-on-write scan isn't portable here. `--claude`
  and `--cursor` can be combined; they share the one precheck script, which
  (like `--claude`) needs `jq` and fails open without it.

- **Conventional-Commits `commit-msg` hook (`install.sh --commit-msg`).**
  Rejects commit subjects that don't match `type(scope): description` (merge /
  revert / fixup commits exempt) and caps the subject at 100 chars (commitlint
  `config-conventional` `header-max-length` parity — runaway subjects wrap in
  `git log` / the GitHub UI and break changelog tooling). Commit format is
  exactly the kind of convention agents drift on across sessions. Zero
  dependencies. (Pairs with `release-please` for automated SemVer releases —
  see [`RECOMMENDATIONS.md`](./RECOMMENDATIONS.md).)

- **gitleaks CI backstop (`install.sh --gitleaks-ci` → `.github/workflows/gitleaks.yml`).**
  Adds a broad, entropy-based secret scanner as a _separate_ CI job. The
  built-in `check-secrets` is a narrow offline regex gate (the specific token
  shapes in `secrets.txt`); gitleaks' ~150 maintained rules catch provider
  tokens the hand-written list can't enumerate. Not auto-installed — it adds a
  third-party action dependency. Follows the same drift-preserving policy as
  the other CI workflows (see [Update & uninstall](#update--uninstall)).
  Pinned to a commit SHA; bump via Dependabot.

- **Local gitleaks pass (`install.sh --gitleaks-hook`).** The fast local echo of
  the gitleaks CI job: a `lib/check-gitleaks` that runs `gitleaks git
--pre-commit --staged --redact` (gitleaks' own official pre-commit invocation)
  over the staged changes. Opt-in, not default-on: a local scan only fires where
  the `gitleaks` binary is installed, so default-on would give two developers
  different commit-time behavior. Fails open (skips with a note) when the binary
  is absent — always pair it with the CI workflow above, which is the
  machine-independent boundary.

- **dependency-review CI gate (`install.sh --dependency-review` →
  `.github/workflows/dependency-review.yml`).** Blocks a PR that introduces a
  dependency with a known vulnerability or a malicious/yanked package (the
  chalk-debug / Shai-Hulud class): the PR-time complement to Dependabot's
  freshness bumps. Opt-in, not default-on, and deliberately so: the action
  needs GitHub's Dependency Graph, on by default for public repos but
  requiring GitHub Advanced Security for private repos, where it errors
  without that entitlement (caveat documented in the template header, same
  "needs a GitHub entitlement" shape as gitleaks for organizations). Pinned to
  a commit SHA; bump via Dependabot. Also ships a conservative AGPL deny-list
  license gate (the action's own license-compliance inputs, left unused by
  the template until now): fails loudly on the one license family that can
  force a consumer's own product open, without the constant false positives
  a broader allow-list would produce for this audience.

- **zizmor CI gate (`install.sh --zizmor-ci` →
  `.github/workflows/zizmor.yml`).** Runs zizmor, a static analyzer for
  GitHub Actions workflows, against your own repo's `.github/workflows/`.
  Its findings map onto real incident classes: unpinned `uses:` refs (the
  mutable-tag vector behind the 2025 tj-actions and 2026 Trivy incidents),
  template-injection via `${{ github.event.* }}` interpolated into a `run:`
  block, credential-persisting checkouts, and over-scoped `GITHUB_TOKEN`
  permissions. Runs `--offline` (static audits only, no `GITHUB_TOKEN` or
  network round-trip, no account or secret needed). Opt-in, not default-on:
  it adds a third-party pip package. Pinned to a commit SHA; bump via
  Dependabot.

- **Red-green test-integrity gate (`install.sh --test-guard` →
  `.githooks/lib/check-red-green` + `.github/workflows/test-guard.yml`).**
  Every NEW test in a PR is run against the base commit in a scratch
  worktree and must FAIL there: a test that passes without the change it
  accompanies was never observed failing, so it is not evidence the change
  works (it tests behaviour that already existed, asserts nothing, or was
  written to match the implementation). Deliberate green-on-base tests
  (characterization before a refactor, coverage backfill) must carry
  `@pytest.mark.characterization(reason=...)`; the marker snippet for
  pytest.ini is printed at install time (pytest.ini is user-owned, so the
  installer never edits it). Also appends a marker-guarded rules section to
  coding-rules.md so agents in the consumer repo see the gate's contract in
  loaded context. Opt-in, not default-on: it assumes a pytest suite and
  roughly doubles CI cost for the new tests in a PR; the vitest half does
  not exist yet. Worth little until made a REQUIRED status check (an
  advisory check a merging agent can route around), which the install note
  says out loud. From the harness review, issue #140 item 2.

  The same gate also runs `check-mutation-diff`, a second layer closing a
  gap red-green cannot: a test can be red on base and still assert nothing
  about the new code's behaviour. It mutates only the lines the PR changed
  and reports every mutant on them the suite fails to kill, per file, using
  mutmut==3.7.0, pinned in CI (`pip install mutmut==3.7.0`, nothing needed
  locally). Per issue #145's advisory-first design, surviving mutants print
  a warning but never fail the job, so the layer can be turned on everywhere
  without becoming a second red-green; only exit code 2 (mutmut missing or
  the wrong pinned version, a broken baseline, a bad worktree/config, or a
  timeout) fails the job, since that means the check could not evaluate
  anything at all, not that it evaluated cleanly. Scoping is file-glob only:
  mutmut 3.x has no function-level scoping, so a large file with one changed
  line still has its whole file mutated.

- **Socket Firewall CI gate (`install.sh --socket-ci` →
  `.github/workflows/socket-security.yml`).** Verifies a package is
  legitimate _before_ it is installed, not after: an LLM coding agent
  hallucinates plausible-but-nonexistent package names at a measurable rate,
  and attackers pre-register those exact names as real packages
  ("slopsquatting"). Neither `check-secrets` nor the dependency-review gate
  above (advisory-DB / known-CVE scoped) catches a freshly registered,
  plausible-looking package with no CVE yet. Uses SocketDev/action in
  firewall-free mode, which shims `npm`/`pnpm`/`yarn`, `pip`/`pip3`/`uv`, and
  `cargo` so install commands are transparently routed through Socket
  Firewall (free tier) and a known-malicious or typosquat package fails the
  install, at install time, with a named package and a reason. No API key or
  account needed for firewall-free mode. Opt-in, not default-on: it adds a
  third-party action dependency. Pinned to a commit SHA; bump via Dependabot.

- **npm install-layer cooldown (`install.sh --npm-cooldown` → `.npmrc`,
  issue #117).** Sets `min-release-age=7`: npm resolves to an older version
  instead of a package version published fewer than 7 days ago. Requires npm
  `>= 11.10.0` (shipped 2026-02-11, npm/cli PR #8965); an older npm treats the
  key as unrecognized, warns, and ignores it, so the install still proceeds
  (fail-open, same shape as `--gitleaks-hook` with no `gitleaks` binary on
  PATH). `.github/dependabot.yml`'s own `cooldown: default-days: 7` only
  holds back Dependabot's own update PRs; it does nothing for an `npm install
<pkg>` a developer or an agent runs by hand, which is exactly the window a
  compromised-and-yanked release (chalk/debug, Shai-Hulud class) is
  installable in. This closes that install-time gap with the same 7-day
  number, rather than a second one to reconcile. `.npmrc` is USER-OWNED
  (`cp_safe`, not `cp_scaffold_preserve`): a project may already have one, or
  may hand-edit the shipped copy, so a re-run never overwrites it without
  `--force`. See the template header for the `before` config interaction
  (an exact date wins over the relative window when both are set).

- **Claude Code Skill (`install.sh --claude-skill` →
  `.claude/skills/coding-rules/SKILL.md`, issue #118 part 2).** Wraps
  `coding-rules.md` and `operational-rules.md` in a Claude Code
  [Skill](https://code.claude.com/docs/en/skills): frontmatter that tells
  Claude Code when to trigger it (before writing/editing code, before a
  commit, or when asked about this project's conventions) and a body that
  tells the agent to read both files in full. This is a **third**, distinct
  loading path, not a replacement for either existing one: `--claude`
  installs _runtime hooks_ (`.claude/settings.json` plus the `PreToolUse`
  precheck) that block a bad tool call as it happens; the plain AGENTS.md
  path (always installed) is _always-loaded context_: CLAUDE.md imports
  `AGENTS.md` (the condensed summary) and the full `coding-rules.md`
  (short by rule, cheap to pin into every turn), while the much larger
  `operational-rules.md` stays a link on purpose, since paying its full
  size on every turn is the wrong trade. `--claude-skill` is what pulls
  the **full text** of `operational-rules.md` (alongside
  `coding-rules.md`) into context **on demand**, at the moments it
  matters, rather than relying on the summary alone. Opt-in because it is
  Claude Code specific; combine freely with `--claude` and with the default
  AGENTS.md install. `.claude/skills/coding-rules/SKILL.md` is USER-OWNED
  (`cp_safe`): a project may hand-edit it, so a re-run never overwrites it
  without `--force`.

- **Patch-coverage gate (`install.sh --coverage-gate` →
  `.github/workflows/coverage.yml`, installed _instead of_ the default-on
  `tests.yml` above).** The one mechanism here that _forces tests
  to be written_: it fails a PR when lines you **added or changed** aren't
  executed by any test (`diff-cover`, default 100% of changed lines; lower the
  `DIFF_COVER_FAIL_UNDER` env to ease adoption, then ratchet up). It deliberately
  does **not** gate on whole-repo coverage %, which lets old untested code mask
  new gaps. Honest ceiling: it forces changed lines to be **executed** by a test,
  never **verified** by one — an assertion-free test still counts as covered.
  Pair it with required human review; for real test-_quality_ signal, layer on
  mutation testing (see [`RECOMMENDATIONS.md`](./RECOMMENDATIONS.md), "Forcing
  tests"). The gate itself stays opt-in because forcing a strict bar on new code
  is a policy choice a team must
  choose deliberately.

  The job also **fails on failing tests**, not only on uncovered lines. That is
  worth stating because it was not always true: the test steps ended in
  `|| true`, so a red suite went green ([#71]). Only `pytest`'s exit 5 (no tests
  collected) is tolerated now, and `vitest` uses `--passWithNoTests` for the
  same case.

Supply-chain hardening is **on by default** in the shipped CI + Dependabot
config: `install.sh` drops a `.github/dependabot.yml` (weekly grouped bumps of
the SHA-pinned Actions, with a **7-day `cooldown`** so a compromised-and-yanked
release is gone before the PR ever appears — delete the file if you don't want
the PRs); the CI frontend job uses a frozen-lockfile install that also passes
**`--ignore-scripts`** (lint/type-check never need a dependency's install hooks,
and the runner holds `GITHUB_TOKEN`); and every `actions/checkout` sets
**`persist-credentials: false`** so the token isn't left in `.git/config` for a
later step or compromised action to read.

## Check whether it's armed

`install.sh` reports what it _wrote_. Whether the guardrails actually _run_ is
a different question, and the gap between the two is where this scaffold's
worst bugs have lived — a foreign `core.hooksPath` (Husky, lefthook, …) that
`install.sh` deliberately leaves alone and only warns about, a hook file
missing its executable bit that git skips without a word, a `secrets.txt`
that went missing and left `check-secrets` exiting 0 silently. Measured on a
real fixture: with that file gone, a genuine `AKIA…` AWS access key commits
clean, with no output at all.

`scaffold-doctor.sh` checks each guardrail's arming mechanism, not just its
presence on disk. It is not installed into your project (see [Scripts (stay
in the scaffold repo)](#what-lands-in-your-project) above), so reach it one
of two ways, run with your project as the current directory:

```sh
npx ai-coding-rules-scaffold doctor              # works no matter how you installed
<path to your scaffold clone>/scaffold-doctor.sh # if you have a git clone
<path to your scaffold clone>/scaffold-doctor.sh --quiet # gaps + summary only, for CI / pre-flight use
```

Each line is `✓` armed, `✗` gap (installed but inert — a commit that should
be blocked isn't), or `!` note (a deliberate off-switch, or an opt-in surface
never opted into — a project that never installed gitleaks is healthy, not
broken). Notes never affect the exit status. Exit `0` means no gaps, `1`
means at least one guardrail is installed but not running, `2` means a usage
error or "not a git repository".

### Paired artifacts (half-installed guardrails)

Some guardrails ship as two halves that only do anything together: a config
file plus the CI workflow that reads it, or a local pre-commit pass plus the
CI gate it defers to. An interrupted install, a later re-run without a flag,
or a hand-copied file can leave only one half on disk, and nothing used to
check again afterward (issue #96: a real downstream repo kept `.coveragerc`
with no `.github/workflows/coverage.yml` for months, every PR green on
`lint.yml` alone). `scaffold-doctor.sh`'s "paired artifacts" section, and
`install.sh`'s own end-of-run summary (same detection, same wording, from
`install-lib.sh`'s `check_paired_artifacts`), name three pairs:

| Pair                                                                                    | Half missing                                                      | Severity                                                                                                 |
| --------------------------------------------------------------------------------------- | ----------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `.coveragerc` / `.github/workflows/coverage.yml`                                        | `.coveragerc` present, `coverage.yml` absent                      | note (the common default: `.coveragerc` ships with every Python install regardless of `--coverage-gate`) |
| `.coveragerc` / `.github/workflows/coverage.yml`                                        | `coverage.yml` present, `.coveragerc` absent, on a Python project | gap (`--coverage-gate` writes both in the same run; only a later deletion produces this)                 |
| local gitleaks hook (`.githooks/lib/check-gitleaks`) / `.github/workflows/gitleaks.yml` | hook present, CI absent                                           | gap (the hook tells every commit that CI is the authoritative gate; there is none)                       |
| local gitleaks hook / gitleaks CI                                                       | CI present, hook absent                                           | note (CI-only is a valid, documented posture)                                                            |
| `tests.yml` / `coverage.yml`                                                            | both present                                                      | note (both run the suite; wasteful, not silent)                                                          |
| `tests.yml` / `coverage.yml`                                                            | neither present, `lint.yml` installed                             | gap (#97's bug restated: CI runs lint only, no test ever executes)                                       |

`scaffold-doctor.sh` sources `install-lib.sh` from its own directory (the same
one it ships alongside in the npm package, the Homebrew formula, and a git
clone) to reuse this logic rather than duplicate it; if that file is ever
missing next to it, the section reports a note instead of silently skipping
it.

### Template drift (installs that predate a release)

`install.sh` never rewrites an existing `AGENTS.md`, and it replaces
`coding-rules.md` only wholesale under `--force`. Both are the right policy
once a file is user-owned: an installer that overwrote local edits on every
run would be worse than one that leaves them alone. The side effect is that
neither file carries a version marker, so a release that adds a section to
either shipped file leaves every prior install silently behind, and the
oldest installs fall furthest.

`scaffold-doctor.sh`'s "template drift" section makes that visible: every
`## ` and `### ` heading in the shipped template becomes the inventory, and
any heading present in the shipped file but missing from the installed one
is named. This is always a note, never a gap, because a section a project
deliberately trimmed is legitimate and must not flip the exit code; the
note names the missing headings and points at the shipped file to diff
against. A doctor run from a copy that does not carry the rest of the
bundle reports that the templates themselves are missing, the same shape as
the pattern-data and paired-artifacts sections above.

A related but stricter case is #136: `coding-rules.md` existing on disk
with no `@coding-rules.md` import line in `CLAUDE.md` is a gap, not a note,
because an unloaded rules file is an unarmed guardrail rather than a
trimmed one.

## Customize per project

- **`coding-rules.md`** — short by design. Add a "Project-specific" section at the bottom for stack rules (SQLAlchemy column quirks, import conventions, architectural constraints).
- **`AGENTS.md`** — the `Project` section is meant to be edited: stack, entry points, gotchas. Keep it tight; agents reread it on every turn.
- **`.forbidden-patterns/*.txt`** — TAB-separated `<regex>\t<description>` lines (one per language, auto-discovered via each file's `# scaffold-extensions:` header). Add deprecated import paths, old service names, etc. Lines starting with `#` are comments; an opt-in TODO/FIXME pattern is pre-seeded as a comment.
- **Whole-tree checks vs. gitignored content** — `npx eslint .` and `pytest` walk what is **on disk**, not what is in git, so a vendored toolchain, an agent worktree, or an extra checkout is inside their blast radius even though CI (fresh checkout, diff-scoped) never sees it. The shipped `eslint.config.js` derives its ignores from your `.gitignore` (via `@eslint/compat`, so add it to the `npm i -D` line); `pytest.ini` ships a `norecursedirs` default, but pytest has **no** `.gitignore` awareness, so extend that list with your own vendored directories by name. Extend the config rather than narrowing the command — a check everyone runs with a hand-picked path has stopped being a gate.
- **`ruff.toml`** — enables `E,F,I,W,B,UP,SIM,PTH,ANN,ASYNC,FAST,G,LOG,BLE,C90,PL,PT,RUF` plus a curated `flake8-bandit` `S` security subset. Trim `ignore = [...]` if a rule fights your style.
- **`.githooks/local.d/`**: project-local checks. Drop an executable in and it runs in both the pre-commit hook and the CI `guardrails` job, under the same contract as the shipped checks: the NUL-delimited file list on stdin, `--ci` as `$1` in CI, non-zero exit blocks. **`install.sh` never writes into this directory**, so an upgrade cannot unwire your checks, which is exactly what happened when the only option was editing `.githooks/pre-commit` (still scaffold-owned and refreshed on re-run) or `.github/workflows/lint.yml` (scaffold-owned but drift-preserving as of #105, see [Update & uninstall](#update--uninstall)). The executable bit is the on/off switch: `chmod -x` disables a check without deleting it. The installed `README.md` in that directory has the full contract and a worked example.
- **Pre-commit hook** — `MAX_LINES=500` by default. Override per-invocation: `MAX_LINES=800 git commit`. Edit the hook to change permanently. The CI workflow reads the same env var.
- **Adopting on an existing codebase** — the local hook scans only staged files. In CI, the scope splits: the **secret and credential-filename scans run whole-tree** (so a pre-existing committed secret or a bad filename surfaces on the first PR even if that PR never touched the file — catching already-committed keys is the whole point); but the **size, forbidden-pattern, and hygiene gates are scoped to the PR/push diff**, so pre-existing oversize files and existing `print()`s are grandfathered until the next time those files change. This matches the behaviour described in [Philosophy](#philosophy) above.

## Update & uninstall

**Update:** re-running `install.sh` is the upgrade path. Scaffold-owned code (the hook, the `lib/check-*` scanners, the `commit-msg` hook) is refreshed whenever it differs from the shipped version (that's how you receive security fixes), and **any file it overwrites is backed up to `<file>.scaffold-bak` first, with a `backed up:` line in the output**, so an edit you made to one is recoverable rather than silently gone. The eight shipped CI workflows (`.github/workflows/lint.yml`, `tests.yml`, `coverage.yml`, `gitleaks.yml`, `dependency-review.yml`, `zizmor.yml`, `socket-security.yml`, `test-guard.yml`) and the `.forbidden-patterns/*.txt` files are scaffold-owned but commonly project-edited (local CI steps added to `lint.yml`, rows appended to a pattern file) or pre-existing under a scaffold-claimed filename (`tests.yml` especially), so they all follow a drift-preserving policy instead: `lint.yml` since #105, `tests.yml`/`coverage.yml`/`gitleaks.yml` since #110, the pattern files and the rest of the workflows since each shipped.

That policy checks provenance, not just today's template: every file it writes is recorded in `.githooks/.scaffold-manifest` (sha256 + scaffold version, see [What lands in your project](#what-lands-in-your-project)), and a re-run of a drift-preserving file compares it against its **own recorded hash**, three ways:

- **Matches its recorded hash:** nobody has touched it since the scaffold last wrote it, so it is refreshed silently to the shipped version and re-recorded, with an `updated:` line, the same as the always-refreshed code above. This is the case the manifest exists for: before it, an untouched install of an older release was indistinguishable from a hand-edit and was kept forever, so a v0.12.0 project could upgrade all the way to HEAD and still carry a `lint.yml` with zero `check-large-files` call sites.
- **Differs from its recorded hash:** a genuine edit (or a file the manifest has no record of writing at its current content). Preserved, and reported with a `note (drift):` line, exactly as before.
- **No manifest entry for the file at all:** an install from before the manifest existed. Falls back to comparing against today's template, the old behavior, so nothing regresses for an install that predates it.

`install.sh --force` replaces the file outright in any of the three cases, backed up first. **Commit `.githooks/.scaffold-manifest`.** It is how your next upgrade, and every teammate's clone, know what the installer actually wrote; delete it and every drift-preserving file reverts to comparing against the current template until the next install rebuilds it. If you have been wiring project-local checks into `.githooks/pre-commit` or `.github/workflows/lint.yml`, move them to `.githooks/local.d/` (see [Customize per project](#customize-per-project)); that directory is never written by an upgrade.

**Marking a customization so an overwrite warns instead of staying silent:** any time a file the installer is about to replace or refresh (a plain `cp_scaffold` refresh, or `--force` on a normally drift-preserving or preserved file) contains a comment line reading `# Repo adaptation: <why>`, the installer prints a loud `warning:` naming that exact line and the path of the `.scaffold-bak` it just wrote, instead of only the routine `backed up:` line. Add this marker next to any edit you make to a scaffold-owned file that a plain drift note would not otherwise protect, most usefully in `.githooks/pre-commit` (refreshed on every re-run, not drift-preserving) or a CI workflow you plan to `--force` past later. It does not stop the overwrite; it makes sure you notice.

Your own config files are a separate case: they're local forks of the templates and are left alone entirely unless you pass `--force`. `install.sh --force` replaces them, backing up each changed file to `<file>.scaffold-bak` first so no edit is lost — and it never overwrites your `CLAUDE.md` (the import block is merged in once) or `AGENTS.md` (left as-is, since its Project section is yours). Diff first:

```sh
diff ~/src/ai-coding-rules-scaffold/ruff.toml.template ruff.toml
# merge in the changes you want; leave your customizations
```

A `git pull` in the scaffold clone picks up new rules / patterns upstream.

**Uninstall** (run from your project root — choose the path that matches how you installed):

- **git-clone install:** run `uninstall.sh` directly from the clone:

  ```sh
  ~/src/ai-coding-rules-scaffold/uninstall.sh            # safe: only unmodified files
  ~/src/ai-coding-rules-scaffold/uninstall.sh --dry-run  # preview
  ~/src/ai-coding-rules-scaffold/uninstall.sh --all      # also nuke AGENTS.md, coding-rules.md, patterns
  ```

- **Homebrew install:** `uninstall.sh` is bundled in the formula's `libexec`:

  ```sh
  bash "$(brew --prefix)/opt/ai-coding-rules-scaffold/libexec/uninstall.sh"
  # add --dry-run or --all as needed
  ```

- **npx install:** there is no persistent on-disk copy of the scaffold, so
  `uninstall.sh` isn't directly available after an npx run. To uninstall,
  clone the repo temporarily and run it from there:
  ```sh
  git clone https://github.com/Sting25/ai-coding-rules-scaffold /tmp/scaffold-uninstall
  /tmp/scaffold-uninstall/uninstall.sh   # run from your project root
  rm -rf /tmp/scaffold-uninstall
  ```

Safe mode only removes files whose content matches the current scaffold template byte-for-byte, so local edits are never lost. `AGENTS.md`, `coding-rules.md`, and `.forbidden-patterns/` are kept unless you pass `--all`. `CLAUDE.md` is treated as a regenerable pointer and removed if unchanged.

**Dropping one language (`--drop-lang=<name>`):** the one partial mode, and the only supported way to stop using a language you installed a pattern file for. `check-patterns` fails closed when `.githooks/.scaffold-manifest` records a `.forbidden-patterns/<name>.txt` that is no longer in the checkout (#159) — an absent file on its own cannot say whether the config was _removed_ or _never installed_, and the entry is what tells them apart, so untracking one can never quietly disarm its rules in CI and in every fresh clone. `install.sh` is purely additive and the manifest carries forward every entry a run did not touch, so a project that genuinely stops using Go needs a way to say so:

```sh
~/src/ai-coding-rules-scaffold/uninstall.sh --drop-lang=go            # removes the file AND its manifest entry
~/src/ai-coding-rules-scaffold/uninstall.sh --dry-run --drop-lang=go  # preview
```

It removes `.forbidden-patterns/go.txt` and that path's manifest line together, leaving the "never installed" state the guard stays silent about, and touches nothing else — commit both changes in the same commit. It is deliberately an explicit, separate invocation: no install or upgrade run ever prunes an entry whose file is missing, because that absence is exactly the signal the guard fires on. Dropping a language that was never installed is a reported no-op, and `secrets.txt` / `shell.txt` are refused — `install.sh` writes both in every mode for every stack, so neither is a language a project can stop using. Do not hand-edit the manifest to silence the guard; use this flag.

## What this scaffold deliberately omits

| Concern                                                       | Where it lives instead                                                                               |
| ------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Architecture / module boundaries                              | Your project spec or design doc                                                                      |
| Framework-specific rules (React Query, specific import paths) | `coding-rules.md` "Project-specific" section                                                         |
| Logging conventions, whole-repo coverage %                    | Per-project decision (the shipped gate measures _patch_ coverage, not a global threshold)            |
| `ruff format` (Python formatting)                             | Drop-in if you want; Python formatting stays opinion-light (TS/JS formatting now ships via Prettier) |
| Spec-first workflow templates (`SPEC.md`)                     | Out of scope — see [`RECOMMENDATIONS.md`](./RECOMMENDATIONS.md)                                      |
| `git worktree` orchestration for parallel agent sessions      | Documented in `AGENTS.md`; not automated                                                             |

## Developing on the scaffold itself

The scaffold can't install itself — `install.sh` refuses to run with the scaffold
directory as the target (it would copy the `*.template` files onto their own
sources). So a fresh clone has **no active hooks** until you bootstrap them:

```sh
scripts/dev-setup.sh
```

This renders the `*.template` sources into the gitignored `.githooks/` and
`.forbidden-patterns/` — the same files `install.sh` writes into a consumer
project and `self-lint.yml` renders in CI — and points `core.hooksPath` at
`.githooks`, so commits in this repo run the scaffold's own guardrails, including
the Conventional-Commits `commit-msg` hook. Edit a `*.template`, re-run the script
to refresh. Only the `*.template` files are tracked; the rendered copies are
build artifacts.

### Shell rules for the scaffold's own scripts

Two rules that used to live in `operational-rules.md` are shell- and
CI-specific and anchored to this repo's own scripts, so they belong here rather
than in a file that installs into other people's projects.

**A conditional must not be a shell function's last command under errexit.**
Under `set -euo pipefail`, a trailing `[[ ... ]] && cmd` makes the function
return 1 on the false path, and a failed command substitution in a bare
assignment aborts the whole script. End helpers with an explicit if/fi so the
negative path returns 0.
_Anchor:_ a sid-guard tightening made a session-start hook abort on routine
stray files; context loading silently stopped, and only independent
verification caught it because the suite passed.

**In cross-platform fallback chains, the noisy-failure variant goes last.**
Order `A || B` so the variant that misbehaves on the wrong platform never runs
first. Some commands "fail" by succeeding partially with garbage on stdout (GNU
`stat -f` prints filesystem stats), which poisons the captured value even
though the fallback also runs.
_Anchor:_ a BSD-first stat chain made a required Linux CI job a coin flip; it
passed for weeks by luck, then failed an unrelated PR.

### End every session on this repo with a rules retrospective

Before handoff, walk the session's incidents against the add-criteria in
`operational-rules.md` and propose additions through this repo's issue flow; a
lesson that lives only in a transcript or a repo-local issue is lost to every
other project. This is a contributor practice for the scaffold itself, which is
why it is not in `operational-rules.md`: that file ships into other people's
repositories, where an instruction to file issues against this tracker does not
belong.
_Anchor:_ an orchestration session filed its lessons as a repo-local issue
only; the owner had to ask explicitly before the generalizable rules were
proposed to the global file every session actually loads.

### Why `scaffold-doctor.sh` reports 2 guardrails "installed but NOT running"

This is expected and deliberate. Read this before "fixing" it.

Since 2026-09-02 the doctor reports a check as a GAP when the script is on disk
but nothing invokes it, rather than calling it armed because the file exists. On
this repo that surfaces two:

| Reported not running      | Why it stays that way                                                                                                                                     |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/check-red-green`     | Part of the opt-in `--test-guard` layer. This repo never opted in, and the gate is built around per-test suites rather than this repo's shell case files. |
| `lib/check-mutation-diff` | Same layer, same reason. Also needs `mutmut`, which this repo does not depend on.                                                                         |

They are present only because `scripts/dev-setup.sh` renders every template it
finds. Wiring them is tracked as item 2 of the harness-adoption issue, not an
oversight.

Two others that used to appear in that list were genuine and were wired on
2026-09-02:

- **`lib/agent-precheck`** now has `.claude/settings.json` invoking it. It was
  installed and unreferenced, so the agent write-guard was nominal.
- **`lib/check-gitleaks`** now has `.github/workflows/gitleaks.yml` behind it.
  The local pass tells developers CI is the authoritative gate; without the
  workflow that statement was untrue for this repo.

If the count changes, something moved. Two is the expected number; anything else
deserves a look rather than a shrug.

## Using this without an AI

The scaffold works fine without any AI tool. Drop the files in, run the hook — same enforcement. `coding-rules.md` is just a named place to put the rules humans should read.

[#71]: https://github.com/Sting25/ai-coding-rules-scaffold/issues/71
