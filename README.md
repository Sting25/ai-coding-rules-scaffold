# ai-coding-rules-scaffold

[![Latest release](https://img.shields.io/github/v/release/Sting25/ai-coding-rules-scaffold)](https://github.com/Sting25/ai-coding-rules-scaffold/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Two-layer enforcement (pre-commit hook + CI mirror) for small teams using AI agents** — catches debug leaks (`print`, `console.log`, `breakpoint`, `pdb`), unbounded file growth, nested-if hell, silenced exceptions, hardcoded secrets/tokens, and stray `.env` or private-key files before they merge. The same `lib/check-*` scripts run in both layers, so the hook and CI can't drift apart and `--no-verify` doesn't become the escape hatch.

Agent-agnostic: works with Cursor, Claude Code, Copilot, Cline, Aider, or no AI at all. Python/FastAPI + TypeScript/React are first-class, with deny-pattern coverage for Vue, Svelte, PHP, Go, Rust, Java, Kotlin, Ruby, and shell — see [Supported stacks](#supported-stacks).

## What it does

Drop-in guardrails that **block bad code from being committed or merged**. One `./install.sh` wires up a local pre-commit hook *and* a matching CI check — both running the same scripts, so nothing slips through and `--no-verify` can't quietly become the team habit.

**What it stops, out of the box:**

- **Debug leftovers** — `print()`, `console.log`, `debugger`, `breakpoint()`, `pdb`/`ipdb`, `dbg!`, `var_dump`, and the per-language equivalents.
- **Secrets & key files** — AWS / GCP / GitHub / GitLab / OpenAI / Anthropic / Stripe / Slack / Docker tokens, private keys, URL-embedded credentials, and stray `.env` / `*.pem` / SSH-key files.
- **Runaway file growth** — a hard **500-line cap** that forces a file to be split before it outgrows an agent's context window (the one rule never to raise).
- **Insecure shortcuts** — `curl | bash`, `rm -rf /`, `chmod 777`, disabled TLS verification (`verify=False`, `curl -k`, `rejectUnauthorized: false`), raw `innerHTML`/XSS sinks, and `git --no-verify` hook bypasses.
- **Repo-hygiene rot** — leftover merge-conflict markers, case-only filename collisions, and hidden-Unicode (Trojan-Source) tricks.
- **Lint & type regressions** — `ruff` for Python; type-aware `eslint` + `tsc` + `prettier` for TS/JS; deny-lists for Vue, Svelte, PHP, Go, Rust, Java, Kotlin, Ruby, and shell.

**How it works:**

- **One command to install** — `./install.sh` drops in the hook, the CI workflow, the rule docs, and per-stack configs, auto-detecting Python vs TS/JS.
- **Two layers, one implementation** — the hook and the CI job call the exact same `lib/check-*` scripts, so they can never drift apart.
- **Agent-agnostic** — rules live in `AGENTS.md` (with a thin `CLAUDE.md` pointer); Cursor, Claude Code, Aider, and others read them directly.
- **Tunable, not all-or-nothing** — per-path size caps and per-rule disable/warn via `.scaffold.toml`, plus inline `# scaffold-allow` for the rare legitimate exception.
- **Cleanly removable** — `./uninstall.sh` reverses everything and never touches the content of your own `CLAUDE.md` / `AGENTS.md`.

## Why this exists

This scaffold came out of working on a large federated geospatial pipeline — Python/FastAPI backend with TypeScript on the front, agents writing in both. The intended audience is small teams (2–5 devs) using Claude Code or a similar agent, often with the AI filling the senior-engineering role on a real codebase.

That setup hits four compounding failure modes that ordinary linting alone doesn't catch:

1. **AI writes inconsistent or conflicting patterns across sessions.** A teammate prompts the agent Monday and it picks one convention; on Wednesday, a different teammate prompts the agent on the same area and it picks a different one. Without machine-checkable rules, the codebase grows three flavors of the same thing — different error-handling shapes, different import styles, different naming. Tools that fail the build on rule violations are the only thing that survives across sessions.

2. **Files grow unboundedly.** Agents add to existing files rather than extract new modules — every request becomes a new function in the same file. Past a certain size the agent can no longer fit the file in context, and the bugs that follow are subtle (the agent can't see the whole file either, so it stops noticing the duplication and inconsistency *it* introduced). The 500-line cap is calibrated well below that threshold so extraction stays cheap.

3. **Debug statements ship silently.** `print()`, `console.log`, `breakpoint()`, `pdb.set_trace()` — agents add them while diagnosing a bug and forget to remove them on the way out. They survive code review because they look like intentional logging at first glance. Commit-time rejection is the only layer that catches them every time.

4. **Forbidden patterns recur.** Agents reach for old import paths, deprecated service names, and outdated idioms because their training data still has them. A per-stack regex deny-list (`backend.txt`, `frontend.txt`, `secrets.txt`, `shell.txt`) is the only durable fix — the agent can't be talked out of recurrent muscle memory, but the build can fail on it.

This scaffold ships the **enforcement layer** that addresses all four directly. Two layers are live: commit-time (the pre-commit hook) and merge-time (the CI mirror), both running the same `lib/check-*` scripts. A third layer — agent-runtime hooks that block bad patterns *before* they're written — is deferred; see [`RECOMMENDATIONS.md`](./RECOMMENDATIONS.md) for the design space and tradeoffs.

What the scaffold doesn't try to solve: parallel-session collisions, context-window discipline across long projects, and spec-first workflows. Those belong to git workflow (`git worktree` per session), nested `CLAUDE.md` files, and project-specific spec docs respectively. Recommended patterns for each are documented in `AGENTS.md` and `RECOMMENDATIONS.md`.

## Philosophy

**Short doc rule list humans remember + full tool enforcement for the rest.** If the build breaks on `ruff C901`, the fix is forced — no one needs to remember that nested-if depth matters.

The file-size rule (max 500 lines) is the one rule to never raise. Every other rule has tradeoffs in specific cases; unbounded file growth is how projects rot.

Enforcement runs in two places, sharing the same scripts:

- **Pre-commit hook** — blocks the commit locally, scanning only your **staged** files. Fast feedback, skippable with `--no-verify`.
- **CI workflow** — blocks the PR server-side. Unskippable.

Both invoke the same `lib/check-*` scripts (`check-size`, `check-patterns`, `check-filenames`, `check-secrets`, `check-hygiene`). The hook and CI can't drift apart because there's nothing to keep in sync — they call the same code. What differs is *scope*. The hook scans your staged files; CI scopes its **quality gates** (ruff, eslint/prettier, and the size / forbidden-pattern / hygiene guardrails) to the **PR/push diff** via the shared `.githooks/lib/ci-changed-files` helper, so installing onto an existing repo doesn't retroactively fail pre-existing code. The **secret and credential-filename scans stay whole-tree** in CI — the non-overridable security boundary, where catching an already-committed key is the whole point. Same scripts everywhere: scoped to the diff for quality gates, whole-tree for secrets. Each script is also runnable on its own (`git ls-files | .githooks/lib/check-secrets`), so you can wire it into Husky, lefthook, or any other orchestrator without rewriting the logic.

## Supported stacks

Two always-on enforcement layers (pre-commit hook + CI mirror) plus optional agent-runtime hooks. What each stack gets:

- **Python** — `ruff` (annotations, complexity, `pathlib`, no-blind-except, async-safety `ASYNC`, FastAPI `FAST`, logging `G`/`LOG`, a curated `flake8-bandit` security subset) **+** a `backend.txt` regex deny-list: `print()`, `breakpoint()`/`pdb`/`ipdb`, `os.path.join`, deprecated `datetime.utcnow()` / `utcfromtimestamp()`. FastAPI (Pydantic responses) and SQLAlchemy-2.0 conventions live in `coding-rules.md`.
- **TypeScript / JavaScript** — type-aware `eslint` (`strictTypeChecked`: floating/misused promises, `switch-exhaustiveness-check`, `preserve-caught-error`, `no-explicit-any`, import sort + unused-import removal) **+** `tsc --noEmit` (against a shipped strict `tsconfig.json`) **+** `prettier --check` (formatting, run separately from eslint) **+** a `frontend.txt` deny-list: `console.log`/`debugger`/`alert`, focused tests (`.only`), `@ts-ignore`/`@ts-nocheck`, hardcoded `localhost`, and TLS-verification-disable (`NODE_TLS_REJECT_UNAUTHORIZED`, `rejectUnauthorized: false`).
  - **React** — `dangerouslySetInnerHTML` (XSS); opt-in `react-hooks` + `jsx-a11y` blocks.
  - **Vue** — `.vue` scanned; `v-html` (XSS).
  - **Svelte** — `.svelte` scanned; `{@html}` (XSS).
- **Testing** — a runner config ships per stack (`vitest.config.ts` for TS/JS unless the project already uses Jest; `pytest.ini` + `.coveragerc` for Python). A runner alone forces nothing; the **opt-in patch-coverage gate** (`--coverage-gate`) fails a PR when *changed* lines ship untested. It gates execution of changed lines, not assertion quality — see [`RECOMMENDATIONS.md`](./RECOMMENDATIONS.md) on why you can't fully machine-force meaningful tests.
- **PHP** — `php -l` syntax + `phpcs` (when configured) **+** `php.txt`: `var_dump`/`print_r`, `->dd()`/`dump()`, `die`/`exit` (opt-in).
- **Go** — `go.txt`: `fmt.Println`/`Printf` debug, `panic`/`print` (opt-in); ready-to-uncomment golangci-lint CI job.
- **Rust** — `rust.txt`: `dbg!`, `println!`, `.unwrap()`/`.expect()` (opt-in); clippy CI job stub.
- **Java / Kotlin** — `java.txt` / `kotlin.txt`: `System.out.println`, `println`, `printStackTrace`; setup-java/Gradle CI stubs.
- **Ruby** — `ruby.txt`: `binding.pry`, `puts` (opt-in); setup-ruby CI stub.
- **Shell** (`*.sh`/`*.bash`) — `shell.txt`: `curl | bash`, `rm -rf /`, `chmod 777`, `git --no-verify` (hook-bypass).
- **Every language / all files** — `secrets.txt` token shapes (AWS `AKIA`/Bedrock, GCP, GitHub, GitLab PAT + runner/deploy/agent tokens, Slack, OpenAI/Anthropic, Stripe, Supabase, OpenRouter, HuggingFace, structural JWTs, private keys, URL-embedded creds), credential-file blocking (`.env`, `*.pem`, SSH keys), the 500-line file-size cap, merge-conflict markers, case-only filename collisions, and hidden-Unicode (Trojan-Source) scanning.

Language pattern files auto-install when their manifest is detected (`go.mod`, `Cargo.toml`, `composer.json`, `pom.xml`/`build.gradle`, `Gemfile`), or install them all with `--all-langs`. Anything not listed still gets the always-on cross-language layers (secrets, file size, filenames, hygiene). Adding a new language is just dropping a `.forbidden-patterns/<lang>.txt` with a `# scaffold-extensions:` header — no script changes.

## Install

**Quickest — `npx`, no clone.** From your project root:

```sh
npx ai-coding-rules-scaffold            # auto-detects Python / JS
npx ai-coding-rules-scaffold --both     # or pick the stack explicitly
```

This fetches the pinned package and runs the same installer documented below —
every flag in the list further down works after `npx ai-coding-rules-scaffold …`.
Needs Node ≥ 14 and `bash` (preinstalled on macOS/Linux; use Git Bash or WSL on
Windows). The package has zero dependencies — it's just the installer + templates.

**Or Homebrew** (macOS/Linux, no Node):

```sh
brew install sting25/tap/ai-coding-rules-scaffold
# then, from your project root:
ai-coding-rules-scaffold            # auto-detects Python / JS
```

**Or clone + run** (language-agnostic, no Node required). Clone the scaffold
somewhere stable:

```sh
# Recommended: pin to a tagged release for reproducibility
git clone --branch v0.9.0 https://github.com/Sting25/ai-coding-rules-scaffold ~/src/ai-coding-rules-scaffold
# Or track main if you want the latest changes
git clone https://github.com/Sting25/ai-coding-rules-scaffold ~/src/ai-coding-rules-scaffold
```

See [Releases](https://github.com/Sting25/ai-coding-rules-scaffold/releases) for available tags.

From your project root:

```sh
~/src/ai-coding-rules-scaffold/install.sh
```

The script auto-detects Python (`pyproject.toml` / `requirements.txt` / `setup.py`) or frontend (`package.json`) and installs the matching pieces. If neither is present, it exits — pass the stack explicitly:

```sh
./install.sh --python       # Python only
./install.sh --frontend     # TS/JS only
./install.sh --both         # both stacks
./install.sh --force        # replace scaffold files (each backed up to .scaffold-bak; CLAUDE.md/AGENTS.md never overwritten)
./install.sh --no-verify    # skip the post-install toolchain check (no detect/offer)
./install.sh --claude       # also install opt-in Claude Code agent guardrails
./install.sh --cursor       # also install opt-in Cursor agent guardrails
./install.sh --commit-msg   # also install the Conventional-Commits commit-msg hook
./install.sh --gitleaks-hook # also install opt-in local gitleaks pre-commit pass
./install.sh --all-langs    # install every language's forbidden-pattern file
./install.sh --coverage-gate # also install the opt-in CI patch-coverage gate
./install.sh --no-install   # detect missing tools but never auto-run a package manager
./install.sh --help         # show usage
```

**Re-running is the upgrade path.** Running `install.sh` again refreshes
scaffold-owned code — the pre-commit hook, the `.githooks/lib/*` scanners, the
`commit-msg` hook, and the `lint.yml` / coverage workflows — whenever it differs
from the shipped version, with no `--force` needed, so pulling a new tag and
re-running delivers security fixes. Your own configs (`ruff.toml`,
`eslint.config.js`, `.scaffold.toml`, the rules docs, …) are left untouched, and
`.forbidden-patterns/*.txt` files you've edited are kept with a drift notice
rather than overwritten (use `--force` to take the shipped version, backed up to
`.scaffold-bak`).

Language pattern files are auto-installed when their manifest is detected
(`go.mod`, `Cargo.toml`, `composer.json`, `pom.xml`/`build.gradle`, `Gemfile`,
…); `--all-langs` installs them all. See [Opt-in layers](#opt-in-layers) for
what `--claude`, `--cursor`, and `--commit-msg` add.

**The scaffold ships configs + enforcement; the tools themselves are project
deps.** At the end, `install.sh` runs a **detect → offer** pass: it checks for
each tool its configs assume (`ruff`, `pytest`+coverage / `eslint`, `tsc`,
`prettier`, `vitest`) and, for anything missing, offers to install it. The
auto-install only runs when it's **safe** — an interactive terminal, not
`--no-verify`, not inside CI (`$CI`), and not `--no-install`. In any
non-interactive context it falls back to just printing the command, so CI and
piped/scripted runs never mutate your `package.json` or environment. The
package manager is detected from your lockfiles (`npm`/`pnpm`/`yarn`,
`pip`/`uv`).

To install the linters by hand instead:

```sh
pip install ruff pytest pytest-cov                                      # Python
npm i -D eslint @eslint/js typescript-eslint typescript prettier vitest # TS/JS
```

### Pairing with Husky / lefthook

If your project already uses Husky or lefthook, `install.sh` detects the existing `core.hooksPath` and won't overwrite it. Two ways forward:

1. **Switch to `.githooks`** — point `core.hooksPath` at `.githooks` and migrate any existing hooks into it. Simplest if your existing hooks are minimal.
2. **Chain** — keep your existing tool and have it invoke the scaffold hook as a step. Husky example:
   ```sh
   # .husky/pre-commit
   .githooks/pre-commit
   ```

Either way, the four `lib/check-*` scripts in `.githooks/lib/` are also runnable directly (`git ls-files | .githooks/lib/check-secrets`), so you can wire them into any orchestrator.

## What lands in your project

| Scaffold file | Installed as | Purpose |
|---|---|---|
| `AGENTS.md.template` | `AGENTS.md` | Primary agent doc: git discipline + project section |
| `CLAUDE.md.pointer` | `CLAUDE.md` | One-liner pointing Claude Code at `AGENTS.md` |
| `coding-rules.md` | `coding-rules.md` | Short list of code-level rules that aren't tool-enforceable |
| `operational-rules.md` | `operational-rules.md` | Process and collaboration rules — failure modes that no linter can catch |
| `ruff.toml.template` | `ruff.toml` | Python lint config |
| `pytest.ini.template` | `pytest.ini` | Python test-runner config (skipped if pyproject/tox already configures pytest) |
| `.coveragerc.template` | `.coveragerc` | coverage.py config for the patch-coverage gate |
| `eslint.config.js.template` | `eslint.config.js` | TS/JS lint config (flat config, ESLint 9+) |
| `tsconfig.json.template` | `tsconfig.json` | Strict TS config the type-aware eslint rules + `tsc --noEmit` assume |
| `.prettierrc.json.template` | `.prettierrc.json` | Prettier formatting config (runs separately from eslint) |
| `.prettierignore.template` | `.prettierignore` | Paths Prettier should not format |
| `vitest.config.ts.template` | `vitest.config.ts` | Vitest runner + V8 coverage config (skipped if the project uses Jest) |
| `githooks/pre-commit.template` | `.githooks/pre-commit` | Hook orchestrator — invokes the five `lib/check-*` scripts |
| `githooks/lib/check-{size,patterns,filenames,secrets,hygiene}.template` | `.githooks/lib/check-{size,patterns,filenames,secrets,hygiene}` | Reusable check scripts; the same scripts run from CI so hook and CI can't drift |
| `githooks/lib/scaffold-config.template` | `.githooks/lib/scaffold-config` | Reads per-project rule overrides from `.scaffold.toml` (per-path size caps, per-rule disable / severity) |
| `githooks/lib/scaffold-audit.template` | `.githooks/lib/scaffold-audit` | Lists every active override in `.scaffold.toml`; run locally and echoed by CI |
| `.scaffold.toml.template` | `.scaffold.toml` | Per-project rule overrides — ships empty (commented), enforces nothing until edited |
| `.github/workflows/lint.yml.template` | `.github/workflows/lint.yml` | CI mirror — invokes the same `lib/check-*` scripts as the hook, scoped to the PR/push diff (`lib/ci-changed-files`) for quality gates, whole-tree for the secret/credential scans |
| `githooks/lib/ci-changed-files.template` | `.githooks/lib/ci-changed-files` | Resolves the PR/push diff so CI quality gates scan only changed files; fails open to the whole tree when there's no diff base |
| `.github/dependabot.yml.template` | `.github/dependabot.yml` | Weekly grouped version bumps for the SHA-pinned GitHub Actions |
| `forbidden-patterns/backend.txt.template` | `.forbidden-patterns/backend.txt` | Python patterns consumed by hook + CI |
| `forbidden-patterns/frontend.txt.template` | `.forbidden-patterns/frontend.txt` | TS/JS patterns consumed by hook + CI |
| `forbidden-patterns/secrets.txt.template` | `.forbidden-patterns/secrets.txt` | Secret/credential patterns, scanned across all file types |
| `forbidden-patterns/shell.txt.template` | `.forbidden-patterns/shell.txt` | Dangerous shell patterns (`curl \| bash`, `rm -rf /`, `chmod 777`) for `*.sh` and `*.bash` |

Scripts (stay in the scaffold repo):

| Script | Purpose |
|---|---|
| `install.sh` | Copy templates into your project, wire `core.hooksPath`, detect/offer the toolchain |
| `uninstall.sh` | Remove unmodified scaffold files, unwire the hook |

## AI agent integration

The scaffold follows the cross-tool **`AGENTS.md` standard** ([agents.md](https://agents.md)) — a single file at the project root that multiple agents already read (Cursor, Aider, Codex, and others). For tools that read a different filename, `install.sh` or a one-line pointer handles it:

- **Cursor** — reads `AGENTS.md` natively. Nothing else needed.
- **Claude Code** — reads `CLAUDE.md`. `install.sh` drops a one-line `CLAUDE.md` containing `@AGENTS.md`, which pulls `AGENTS.md` into context.
- **Aider** — add to `.aider.conf.yml`:
  ```yaml
  read:
    - AGENTS.md
    - coding-rules.md
    - operational-rules.md
  ```
- **Cline** — create `.clinerules` with one line:
  ```
  Follow the rules in AGENTS.md, coding-rules.md, and operational-rules.md.
  ```
- **Continue / Copilot / other** — point the tool at `AGENTS.md` via whatever config it supports.

### Use the rules without the rest of the scaffold

You can use `operational-rules.md` (and/or `coding-rules.md`) standalone, without the linter / hook / CI scaffolding. Drop the file(s) into your project root and reference them from your AI tool's config:

- **Claude Code** — add to `CLAUDE.md`:
  ```
  @operational-rules.md
  @coding-rules.md
  ```
  The `@` directive auto-loads on session start.
- **Cursor / Aider / Cline / etc.** — add the filename(s) to whatever config the tool reads every session (`.cursorrules`, `.aider.conf.yml`, `.clinerules`).

No `install.sh`, no hooks, no CI — the docs are useful in isolation. The full scaffold layers on the enforcement (commit hooks + CI mirror) that turns the rules into machine-checkable failures.

### Scaling context across a large codebase

Root-level `AGENTS.md` is reread on every turn, so its token cost is paid for every prompt. For codebases over ~50 files, drop a nested `AGENTS.md` in each major directory (`app/api/`, `app/web/`, `lib/`) with area-specific gotchas — the standard specifies closest-file-wins, so agents read the nearest one walking up from the file being edited, keeping root-level context small and area context relevant. For Claude Code, a nested `CLAUDE.md` works the same way.

For parallel agent sessions, use `git worktree add ../proj-feat-x -b feat-x` so each session has an isolated working tree on its own branch. Two agents in the same checkout will overwrite each other.

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

| Concern | Rule |
|---|---|
| Nested control flow > 3 deep | `ruff C901`, `eslint max-depth: 3` |
| Cyclomatic complexity > 10 | `ruff C901`, `eslint complexity: 10` |
| `os.path.join` / string path math | `ruff PTH100-208` |
| Blind `except Exception: pass` | `ruff BLE001` |
| Missing public-API return types | `ruff ANN201` |
| Function size > 80 statements (Python) / 80 lines (TS/JS) | `ruff PLR0915` (`max-statements`), `eslint max-lines-per-function` |
| Too many branches in a function | `ruff PLR0912` (`max-branches`) |
| Blocking HTTP/file/subprocess call inside `async def` | `ruff ASYNC210-230` |
| Non-`Annotated` FastAPI dependency / unused path param | `ruff FAST002`, `FAST003` |
| f-string / `%` / `.format()` in a logging call; `.warn()` / root logger | `ruff G002 G004 G010 LOG` |
| `shell=True` / `eval` / unsafe deserialization (`pickle`) / weak hash | `ruff S` (curated flake8-bandit subset) |
| Line length > 100 | `ruff E501` |
| Unsorted / unused imports | `ruff I`, `F401`; `eslint import-x/order`, `unused-imports/no-unused-imports` |
| `any` in TypeScript without comment | `@typescript-eslint/no-explicit-any` |
| Floating / misused promises (TS) | `@typescript-eslint/no-floating-promises`, `no-misused-promises` (type-aware) |
| Non-exhaustive `switch` over a union/enum (missing member) | `@typescript-eslint/switch-exhaustiveness-check` (type-aware) |
| Re-throwing in `catch` while discarding the original error cause/stack | `eslint preserve-caught-error` (needs ESLint ≥ 9.35) |
| TypeScript type errors | `tsc --noEmit` (hook + CI, when `tsconfig.json` present) |
| Unformatted TS/JS | `prettier --check` (hook + CI, when a prettier config is present; `prettier --write` fixes) |
| Changed lines shipped without a test (opt-in) | `diff-cover` patch-coverage gate (`--coverage-gate`, CI) |

Commit + CI-breaking (pre-commit hook + `lint.yml`):

| Concern | Check |
|---|---|
| `print()`, `breakpoint()`, `pdb`/`ipdb.set_trace()`, `os.path.join`, deprecated `datetime.utcnow()`/`utcfromtimestamp()` in Python files | regex (backend.txt) |
| `console.log` / `debugger` / `alert` in TS/JS | regex (frontend.txt) |
| XSS sinks — `dangerouslySetInnerHTML` (React), `v-html` (Vue, `.vue`), `{@html}` (Svelte, `.svelte`) | regex (frontend.txt) |
| Focused tests (`.only`), `@ts-ignore` / `@ts-nocheck`, hardcoded `localhost`/`127.0.0.1` URLs, TLS-verification-disable (`NODE_TLS_REJECT_UNAUTHORIZED`, `rejectUnauthorized: false`) | regex (frontend.txt) |
| Dangerous shell in `*.sh`/`*.bash` — `curl \| bash`, `rm -rf /`, `chmod 777`, `git --no-verify` (hook bypass) | regex (shell.txt) |
| File size > 500 lines | line count of the staged blob (`git show :0:<path>`, counting a final line with no trailing newline) |
| TODO/FIXME without ticket ref | regex (opt-in; commented in template) |
| Secret / credential leaks (AWS `AKIA`/Bedrock, GitHub/GitLab tokens, Stripe, Supabase, OpenRouter, OpenAI/Anthropic, structural JWTs, private keys, URLs with embedded credentials, quoted hardcoded `password`/`token`/`api_key` assignments — unquoted/env-var forms are better caught by the gitleaks layer below) | regex (case-insensitive). Scans **every** tracked file's staged blob as text (no extension allowlist, so renaming a payload can't skip it); NUL bytes are stripped so they can't hide content. A single line longer than `MAX_LINE_LENGTH` (50000) is dropped before the regex (so a minified/binary blob can't hang the scan) and the file is then **rejected as unscannable** (fail-closed) — split/relocate the asset, raise `MAX_LINE_LENGTH`, or point a dedicated scanner at it |
| Committed `.env` / `*.pem` / SSH private keys (`id_rsa`, `id_ed25519`, `id_ecdsa`, `id_dsa`) | filename check (`.env.example` / `.env.sample` / `.env.template` allowed) |
| Merge-conflict markers (`<<<<<<<` / `\|\|\|\|\|\|\|` / `>>>>>>>`) left in a file | `check-hygiene` (staged-blob scan) |
| Case-only filename collisions (`Readme.md` vs `README.md`) that break macOS/Windows checkouts | `check-hygiene` (path scan; diff-scoped in CI like the other quality gates) |
| Hidden Unicode — bidi controls (Trojan Source), zero-width, tag block — in a staged text file | `check-hygiene` (LC_ALL=C byte scan; leading BOM allowed, binary skipped) |

### Per-line escape valve

When a regex match is intentional — a CLI entry point that needs `print`,
a docs example showing an AWS key prefix, a fixture with a synthetic
credential — append `scaffold-allow` (any case, in a comment) on the
matched line. `check-patterns` and `check-secrets` skip lines containing
the marker; `check-filenames` and `check-size` are file-level and
unaffected. See `forbidden-patterns/README.md` for examples.

**Reviewers: every PR that adds or moves a `scaffold-allow` marker is
suppressing a guardrail.** Treat new markers like new `# noqa`s — confirm
the suppression is justified before approving. Audit the full set with
`git grep -i scaffold-allow`.

### Per-project rule overrides (`.scaffold.toml`)

`scaffold-allow` exempts a single *line*. When a team disagrees with a rule
*as a whole* — or needs a bigger size budget for a legacy tree — record that
decision once, durably and auditably, in a repo-root `.scaffold.toml`. It
ships empty (all examples commented), so it changes nothing until you edit it.

```toml
[size]
default     = 800          # raise the project-wide line cap (default 500)
"legacy/**" = 2000         # most-specific matching glob wins

[rules."php/var_dump( or print_r( left in code"]
disabled = true            # turn a forbidden-pattern rule off entirely
reason   = "legacy reporting module, JIRA-1234"
by       = "alex 2026-06-11"

[rules."frontend/console.log left in code"]
severity = "warn"          # error (default) → warn: still reported, doesn't fail

[rules.case-collision]     # hygiene ids: conflict-marker, case-collision
severity = "warn"
```

- **Rule ids.** Forbidden-pattern rules are keyed `"<patternfile-stem>/<description>"`
  (the text after the TAB in `.forbidden-patterns/<lang>.txt`). Hygiene rules
  use `conflict-marker` / `case-collision`; the size cap uses `size`.
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

## Opt-in layers

Beyond the always-on hook + CI mirror, three extras are available. They're off
by default so the scaffold stays minimal; turn them on per project.

- **Agent-runtime guardrails (`install.sh --claude`).** The deferred "layer
  three" — catching bad input *before* the agent writes it, not at commit time.
  Installs a `.claude/settings.json` that denies the agent reading credential
  files (`.env`, `*.pem`, `*.key`, `~/.ssh/**`, `~/.aws/**`, …) and a
  `PreToolUse` hook (`.githooks/lib/agent-precheck`) that scans Write/Edit/Bash
  content against the *same* `.forbidden-patterns/secrets.txt` the commit-time
  scanner uses — one rule set across agent → commit → CI. Needs `jq` (fails open
  without it). See [`RECOMMENDATIONS.md`](./RECOMMENDATIONS.md).

- **Cursor agent guardrails (`install.sh --cursor`).** The same `agent-precheck`
  wired to Cursor's `beforeShellExecution` hook via `.cursor/hooks.json`, so a
  `curl | bash` / `rm -rf /` / `chmod 777` the agent is about to run is scanned
  against `.forbidden-patterns/shell.txt` and blocked (exit 2 = Cursor deny).
  Cursor has no before-write hook, so unlike `--claude` the secret-on-write scan
  and credential read deny-list aren't portable — the shell-command scan is the
  high-ROI piece that is. `--claude` and `--cursor` can be combined; they share
  the one precheck script, which (like `--claude`) needs `jq` and fails open
  without it.

- **Conventional-Commits `commit-msg` hook (`install.sh --commit-msg`).**
  Rejects commit subjects that don't match `type(scope): description` (merge /
  revert / fixup commits exempt) and caps the subject at 100 chars (commitlint
  `config-conventional` `header-max-length` parity — runaway subjects wrap in
  `git log` / the GitHub UI and break changelog tooling). Commit format is
  exactly the kind of convention agents drift on across sessions. Zero
  dependencies. (Pairs with `release-please` for automated SemVer releases —
  see [`RECOMMENDATIONS.md`](./RECOMMENDATIONS.md).)

- **gitleaks CI backstop (`.github/workflows/gitleaks.yml.template`).** Copy it
  in to add a broad, entropy-based secret scanner as a *separate* CI job. The
  built-in `check-secrets` is a narrow offline regex gate (the specific token
  shapes in `secrets.txt`); gitleaks' ~150 maintained rules catch provider
  tokens the hand-written list can't enumerate. Not auto-installed — it adds a
  third-party action dependency. Pinned to a commit SHA; bump via Dependabot.

- **Local gitleaks pass (`install.sh --gitleaks-hook`).** The fast local echo of
  the gitleaks CI job: a `lib/check-gitleaks` that runs `gitleaks git
  --pre-commit --staged --redact` (gitleaks' own official pre-commit invocation)
  over the staged changes. Opt-in, not default-on: a local scan only fires where
  the `gitleaks` binary is installed, so default-on would give two developers
  different commit-time behavior. Fails open (skips with a note) when the binary
  is absent — always pair it with the CI workflow above, which is the
  machine-independent boundary.

- **dependency-review CI gate (`.github/workflows/dependency-review.yml.template`).**
  Copy it in to block a PR that introduces a dependency with a known
  vulnerability or a malicious/yanked package (the chalk-debug / Shai-Hulud
  class) — the PR-time complement to Dependabot's freshness bumps. Not
  auto-installed; pinned to a commit SHA. **Needs GitHub's Dependency Graph:**
  on by default for public repos, requires GitHub Advanced Security for private
  repos (caveat documented in the template header).

- **Patch-coverage gate (`install.sh --coverage-gate` →
  `.github/workflows/coverage.yml`).** The one mechanism here that *forces tests
  to be written*: it fails a PR when lines you **added or changed** aren't
  executed by any test (`diff-cover`, default 100% of changed lines; lower the
  `DIFF_COVER_FAIL_UNDER` env to ease adoption, then ratchet up). It deliberately
  does **not** gate on whole-repo coverage %, which lets old untested code mask
  new gaps. Honest ceiling: it forces changed lines to be **executed** by a test,
  never **verified** by one — an assertion-free test still counts as covered.
  Pair it with required human review; for real test-*quality* signal, layer on
  mutation testing (see [`RECOMMENDATIONS.md`](./RECOMMENDATIONS.md), "Forcing
  tests"). Opt-in because forcing tests on new code is a policy a team must
  choose deliberately.

Supply-chain hardening is **on by default** in the shipped CI + Dependabot
config: `install.sh` drops a `.github/dependabot.yml` (weekly grouped bumps of
the SHA-pinned Actions, with a **7-day `cooldown`** so a compromised-and-yanked
release is gone before the PR ever appears — delete the file if you don't want
the PRs); the CI frontend job uses a frozen-lockfile install that also passes
**`--ignore-scripts`** (lint/type-check never need a dependency's install hooks,
and the runner holds `GITHUB_TOKEN`); and every `actions/checkout` sets
**`persist-credentials: false`** so the token isn't left in `.git/config` for a
later step or compromised action to read.

## Verify it works

After install, confirm the hook rejects bad code:

```sh
echo 'print("test")' >> some_module.py
git add some_module.py
git commit -m "should be rejected"
# → hook prints: ✗ some_module.py: Use structlog (or the project's logger), not print()
```

## Customize per project

- **`coding-rules.md`** — short by design. Add a "Project-specific" section at the bottom for stack rules (SQLAlchemy column quirks, import conventions, architectural constraints).
- **`AGENTS.md`** — the `Project` section is meant to be edited: stack, entry points, gotchas. Keep it tight; agents reread it on every turn.
- **`.forbidden-patterns/*.txt`** — TAB-separated `<regex>\t<description>` lines (one per language, auto-discovered via each file's `# scaffold-extensions:` header). Add deprecated import paths, old service names, etc. Lines starting with `#` are comments; an opt-in TODO/FIXME pattern is pre-seeded as a comment.
- **`ruff.toml`** — enables `E,F,I,W,B,UP,SIM,PTH,ANN,ASYNC,FAST,G,LOG,BLE,C90,PL,PT,RUF` plus a curated `flake8-bandit` `S` security subset. Trim `ignore = [...]` if a rule fights your style.
- **Pre-commit hook** — `MAX_LINES=500` by default. Override per-invocation: `MAX_LINES=800 git commit`. Edit the hook to change permanently. The CI workflow reads the same env var.
- **Adopting on an existing codebase** — the local hook scans only the files in a given commit, but the CI job scans *all* tracked files (size, patterns, filenames, and secrets alike), not just changed ones. So the first PR after adoption surfaces pre-existing debt: a file already over 500 lines, an existing `print()`, or a secret already in history all fail in CI even if the PR didn't touch them. For the size case, extract the offenders first (preferred — this is the debt the rule is meant to catch) or set `MAX_LINES` higher temporarily in both the hook and CI, then ratchet it down as you refactor.

## Update & uninstall

**Update:** the project's configs are local forks of the templates. `install.sh --force` replaces them, backing up each changed file to `<file>.scaffold-bak` first so no edit is lost — and it never overwrites your `CLAUDE.md` (the import block is merged in once) or `AGENTS.md` (left as-is, since its Project section is yours). Diff first:

```sh
diff ~/src/ai-coding-rules-scaffold/ruff.toml.template ruff.toml
# merge in the changes you want; leave your customizations
```

A `git pull` in the scaffold clone picks up new rules / patterns upstream.

**Uninstall:**

```sh
~/src/ai-coding-rules-scaffold/uninstall.sh            # safe: only unmodified files
~/src/ai-coding-rules-scaffold/uninstall.sh --dry-run  # preview
~/src/ai-coding-rules-scaffold/uninstall.sh --all      # also nuke AGENTS.md, coding-rules.md, patterns
```

Safe mode only removes files whose content matches the current scaffold template byte-for-byte, so local edits are never lost. `AGENTS.md`, `coding-rules.md`, and `.forbidden-patterns/` are kept unless you pass `--all`. `CLAUDE.md` is treated as a regenerable pointer and removed if unchanged.

## Platform notes

- **macOS / Linux:** first-class.
- **Windows:** use Git Bash or WSL. The pre-commit hook is `bash`; Git Bash (bundled with Git for Windows) runs it fine. `chmod +x` is a no-op on NTFS, but Git for Windows treats shell scripts in `.githooks/` as executable regardless.

## What this scaffold deliberately omits

| Concern | Where it lives instead |
|---|---|
| Architecture / module boundaries | Your project spec or design doc |
| Framework-specific rules (React Query, specific import paths) | `coding-rules.md` "Project-specific" section |
| Logging conventions, whole-repo coverage % | Per-project decision (the shipped gate measures *patch* coverage, not a global threshold) |
| `ruff format` (Python formatting) | Drop-in if you want; Python formatting stays opinion-light (TS/JS formatting now ships via Prettier) |
| Spec-first workflow templates (`SPEC.md`) | Out of scope — see [`RECOMMENDATIONS.md`](./RECOMMENDATIONS.md) |
| Claude Code agent-runtime hooks (`.claude/settings.json` `PreToolUse`) | Deferred — see [`RECOMMENDATIONS.md`](./RECOMMENDATIONS.md) for design space and tradeoffs |
| `git worktree` orchestration for parallel agent sessions | Documented in `AGENTS.md`; not automated |

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

## Using this without an AI

The scaffold works fine without any AI tool. Drop the files in, run the hook — same enforcement. `coding-rules.md` is just a named place to put the rules humans should read.

## License

MIT — see [LICENSE](LICENSE).
