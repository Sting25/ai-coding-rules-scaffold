# ai-coding-rules-scaffold

[![Latest release](https://img.shields.io/github/v/release/Sting25/ai-coding-rules-scaffold)](https://github.com/Sting25/ai-coding-rules-scaffold/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Two-layer enforcement (pre-commit hook + CI mirror) for small teams using AI agents** — catches debug leaks (`print`, `console.log`, `breakpoint`, `pdb`), unbounded file growth, nested-if hell, silenced exceptions, hardcoded secrets/tokens, and stray `.env` or private-key files before they merge. The same `lib/check-*` scripts run in both layers, so the hook and CI can't drift apart and `--no-verify` doesn't become the escape hatch.

Agent-agnostic: works with Cursor, Claude Code, Copilot, Cline, Aider, or no AI at all. Python/FastAPI + TypeScript/React are first-class, with deny-pattern coverage for Vue, Svelte, PHP, Go, Rust, Java, Kotlin, Ruby, and shell — see [Supported stacks](./TECHNICAL.md#supported-stacks) in TECHNICAL.md.

## What it does

Drop-in guardrails that **block bad code from being committed or merged**. One `./install.sh` wires up a local pre-commit hook _and_ a matching CI check — both running the same scripts, so nothing slips through and `--no-verify` can't quietly become the team habit.

**What it stops, out of the box:**

- **Debug leftovers** — `print()`, `console.log`, `debugger`, `breakpoint()`, `pdb`/`ipdb`, `dbg!`, `var_dump`, and the per-language equivalents.
- **Secrets & key files** — AWS / GCP / GitHub / GitLab / OpenAI / Anthropic / Stripe / Slack / Docker tokens, private keys, URL-embedded credentials, and stray `.env` / `*.pem` / SSH-key files.
- **Runaway file growth**, a hard **500-line cap** that forces a file to be split before it outgrows an agent's context window (the one rule never to raise), plus a **500 KB cap** on any single committed file that blocks large binaries (videos, model checkpoints, database dumps, zipped exports).
- **Insecure shortcuts** — `curl | bash`, `rm -rf /`, `chmod 777`, disabled TLS verification (`verify=False`, `curl -k`, `rejectUnauthorized: false`), raw `innerHTML`/XSS sinks, and `git --no-verify` hook bypasses.
- **Repo-hygiene rot** — leftover merge-conflict markers, case-only filename collisions, and hidden-Unicode (Trojan-Source) tricks.
- **Lint & type regressions** — `ruff` for Python; type-aware `eslint` + `tsc` + `prettier` for TS/JS; deny-lists for Vue, Svelte, PHP, Go, Rust, Java, Kotlin, Ruby, and shell.

**How it works:**

- **One command to install** — `./install.sh` drops in the hook, the CI workflow, the rule docs, and per-stack configs, auto-detecting Python vs TS/JS.
- **Two layers, one implementation** — the hook and the CI job call the exact same `lib/check-*` scripts, so they can never drift apart.
- **Agent-agnostic** — rules live in `AGENTS.md` (with a thin `CLAUDE.md` pointer); Cursor, Claude Code, Aider, and others read them directly.
- **Tunable, not all-or-nothing** — per-path size caps and per-rule disable/warn via `.scaffold.toml`, plus inline `# scaffold-allow` for the rare legitimate exception.
- **Cleanly removable** — `uninstall.sh` reverses everything and never touches the content of your own `CLAUDE.md` / `AGENTS.md` (see [Update & uninstall](./TECHNICAL.md#update--uninstall) in TECHNICAL.md for how to run it per install method).

Full reference detail lives in [TECHNICAL.md](./TECHNICAL.md): every rule the tooling enforces, the file-by-file inventory of what lands in your project, per-project customization (`.scaffold.toml`, per-line escape valves), and update/uninstall instructions. This README stays focused on what the scaffold does and how to get it running.

## Why this exists

This scaffold came out of working on a large federated geospatial pipeline — Python/FastAPI backend with TypeScript on the front, agents writing in both. The intended audience is small teams (2–5 devs) using Claude Code or a similar agent, often with the AI filling the senior-engineering role on a real codebase.

That setup hits four compounding failure modes that ordinary linting alone doesn't catch:

1. **AI writes inconsistent or conflicting patterns across sessions.** A teammate prompts the agent Monday and it picks one convention; on Wednesday, a different teammate prompts the agent on the same area and it picks a different one. Without machine-checkable rules, the codebase grows three flavors of the same thing — different error-handling shapes, different import styles, different naming. Tools that fail the build on rule violations are the only thing that survives across sessions.

2. **Files grow unboundedly.** Agents add to existing files rather than extract new modules — every request becomes a new function in the same file. Past a certain size the agent can no longer fit the file in context, and the bugs that follow are subtle (the agent can't see the whole file either, so it stops noticing the duplication and inconsistency _it_ introduced). The 500-line cap is calibrated well below that threshold so extraction stays cheap.

3. **Debug statements ship silently.** `print()`, `console.log`, `breakpoint()`, `pdb.set_trace()` — agents add them while diagnosing a bug and forget to remove them on the way out. They survive code review because they look like intentional logging at first glance. Commit-time rejection is the only layer that catches them every time.

4. **Forbidden patterns recur.** Agents reach for old import paths, deprecated service names, and outdated idioms because their training data still has them. A per-stack regex deny-list (`backend.txt`, `frontend.txt`, `secrets.txt`, `shell.txt`) is the only durable fix — the agent can't be talked out of recurrent muscle memory, but the build can fail on it.

This scaffold ships the **enforcement layer** that addresses all four directly. Two layers are always-on: commit-time (the pre-commit hook) and merge-time (the CI mirror), both running the same `lib/check-*` scripts. A third opt-in layer — agent-runtime hooks that block bad patterns _before_ they're written — ships via `install.sh --claude` (Claude Code) and `install.sh --cursor` (Cursor); see [Opt-in layers](./TECHNICAL.md#opt-in-layers) in TECHNICAL.md and [`RECOMMENDATIONS.md`](./RECOMMENDATIONS.md) for the design space and tradeoffs.

What the scaffold doesn't try to solve: parallel-session collisions, context-window discipline across long projects, and spec-first workflows. Those belong to git workflow (`git worktree` per session), nested `CLAUDE.md` files, and project-specific spec docs respectively. Recommended patterns for each are documented in `AGENTS.md` and `RECOMMENDATIONS.md`.

## Install

> **AI agents, and anyone adopting this on an existing codebase:** you do not need the installer. [COMPONENTS.md](COMPONENTS.md) lists every component with what it blocks, its blast radius (staged files only, or project-wide), the exact copy commands, a verify command that proves the guard is armed, and how to remove it. Start with `npx ai-coding-rules-scaffold assess`, which measures what each component would flag in this repo and writes nothing. Then pick what you want, run the adopt block, run the verify block, then `scaffold-doctor.sh`. The project-wide entries (tsconfig, ruff, eslint) carry a measurement command to run first with nothing copied; that is how you avoid thousands of findings on day one. The installer below performs the same copies for you in one go. If it errors or is blocked, stop and show your user the error instead of working around it.

**Recommended: clone it, then take what you want.** No package manager, no
installer. Clone a pinned tag, read [COMPONENTS.md](COMPONENTS.md), and copy
the components you want with the commands in each entry; every entry has a
verify step, and `scaffold-assess.sh` measures what each would flag first.

```sh
git clone --branch v0.19.0 https://github.com/Sting25/ai-coding-rules-scaffold ~/src/ai-coding-rules-scaffold
export SCAFFOLD=~/src/ai-coding-rules-scaffold
bash "$SCAFFOLD/scaffold-assess.sh"        # from your project root: what would each component flag?
```

The rest of this section is the installer, which does the same copies in one
go. It is a convenience and the paths below are alternatives to each other.

**`npx`, no clone.** From your project root:

```sh
npx ai-coding-rules-scaffold                  # auto-detects Python / JS
npx ai-coding-rules-scaffold --both           # or pick the stack explicitly
npx ai-coding-rules-scaffold --both --claude  # + AI-agent guardrails (also --cursor)
```

This fetches the published package and runs the same installer documented below —
every flag in the list further down works after `npx ai-coding-rules-scaffold …`.
To upgrade, run `npx ai-coding-rules-scaffold@latest` (the `@latest` tag forces
npm to re-resolve the current release, bypassing any cached version — bare-spec
`npx` on npm 7–8 can silently reuse a stale cached copy and skip the upgrade).
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
git clone --branch v0.19.0 https://github.com/Sting25/ai-coding-rules-scaffold ~/src/ai-coding-rules-scaffold
# Or track main if you want the latest changes
git clone https://github.com/Sting25/ai-coding-rules-scaffold ~/src/ai-coding-rules-scaffold
```

See [Releases](https://github.com/Sting25/ai-coding-rules-scaffold/releases) for available tags.

From your project root:

```sh
~/src/ai-coding-rules-scaffold/install.sh
```

The script auto-detects Python (`pyproject.toml` / `requirements.txt` / `setup.py`) or frontend (`package.json`) and installs the matching pieces. If neither is present, it falls back to **shell mode** when the repo contains any `*.sh`/`*.bash` file (tracked or not yet committed); with no manifest and no shell scripts it exits and asks for the stack explicitly. A manifest always wins over the shell fallback, so a `package.json` project that also ships build scripts is still a frontend install.

Tests run in CI by default: a plain install also drops `.github/workflows/tests.yml`, so pytest/vitest execute on every PR/push with no coverage threshold. `--coverage-gate` swaps that for the stricter patch-coverage gate; `--no-test-workflow` opts out entirely (loudly, with a recorded skip in the install summary) for a repo that genuinely cannot run tests in CI.

```sh
./install.sh --python       # Python only
./install.sh --frontend     # TS/JS only
./install.sh --both         # both stacks
./install.sh --shell        # shell-only project (no Python/TS manifest) — hooks + shell/secrets patterns only
./install.sh --force        # replace scaffold files (each backed up to .scaffold-bak; CLAUDE.md/AGENTS.md never overwritten)
./install.sh --no-verify    # skip the post-install toolchain check (no detect/offer)
./install.sh --claude       # also install opt-in Claude Code agent guardrails
./install.sh --cursor       # also install opt-in Cursor agent guardrails
./install.sh --commit-msg   # also install the Conventional-Commits commit-msg hook
./install.sh --gitleaks-hook # also install opt-in local gitleaks pre-commit pass
./install.sh --gitleaks-ci  # also install the gitleaks CI workflow (unskippable gate)
./install.sh --dependency-review # also install the dependency-review CI gate (opt-in: needs GitHub Advanced Security on a private repo, or it errors)
./install.sh --zizmor-ci    # also install the zizmor GitHub Actions audit gate (opt-in: adds a third-party pip package)
./install.sh --socket-ci    # also install the Socket Firewall supply-chain gate (opt-in: adds a third-party action dependency)
./install.sh --test-guard   # also install the red-green test-integrity gate (a new test must fail on the PR base before it may pass), plus an advisory diff-scoped mutation layer
./install.sh --npm-cooldown # also install .npmrc's min-release-age package cooldown (opt-in: needs npm >= 11.10.0, older npm just warns and ignores it)
./install.sh --claude-skill # also install an on-demand Claude Code Skill wrapping coding-rules.md/operational-rules.md
./install.sh --all-langs    # install every language's forbidden-pattern file
./install.sh --coverage-gate # swap the default tests.yml for coverage.yml (tests + patch-coverage gate)
./install.sh --no-test-workflow # opt out of the default CI test-execution workflow (loud recorded skip)
./install.sh --no-install   # detect missing tools but never auto-run a package manager
./install.sh --interactive  # wizard: prompts for stack + each opt-in flag above (-i, needs a terminal)
./install.sh --help         # show usage
```

Before it copies anything else, every run (including the first) adds
`*.scaffold-bak`, `*.scaffold-bak.*`, `.githooks/.scaffold-manifest.new.*` and
`.githooks/.scaffold-manifest.tmp.*` to your `.gitignore`, creating the file
if you don't already have one, so an upgrade's backup copies never end up
tracked. That happens before the symlink checks that can make the rest of
the run refuse to write and exit non-zero, so a failed install still leaves
this `.gitignore` change behind. See [What lands in your project](./TECHNICAL.md#what-lands-in-your-project)
in TECHNICAL.md.

**Re-running is the upgrade path.** Running `install.sh` again refreshes
scaffold-owned code: the pre-commit hook, the `.githooks/lib/*` scanners, and
the `commit-msg` hook, whenever it differs from the shipped version, with no
`--force` needed, so pulling a new tag and re-running delivers security
fixes. Your own configs (`ruff.toml`, `eslint.config.js`, `.scaffold.toml`,
the rules docs, …) are left untouched, and `.forbidden-patterns/*.txt` files
and the CI workflows (`lint.yml`, `tests.yml`, `coverage.yml`, `gitleaks.yml`,
`dependency-review.yml`, `zizmor.yml`, `socket-security.yml`, `test-guard.yml`)
that you've edited are kept with a drift notice rather than overwritten (use
`--force` to take the shipped version, backed up to `.scaffold-bak`). Any
scaffold-owned file the installer does overwrite is backed up first, and if
that file contains a `# Repo adaptation: <why>` comment line, the installer
prints a loud warning naming it instead of only the routine `backed up:`
line, so a customization to a file that would otherwise be silently
refreshed gets noticed. See [Update & uninstall](./TECHNICAL.md#update--uninstall)
in TECHNICAL.md for the full contract.

Language pattern files are auto-installed when their manifest is detected
(`go.mod`, `Cargo.toml`, `composer.json`, `pom.xml`/`build.gradle`, `Gemfile`,
…); `--all-langs` installs them all. See [Opt-in layers](./TECHNICAL.md#opt-in-layers)
in TECHNICAL.md for what `--claude`, `--cursor`, and `--commit-msg` add.

**The scaffold ships configs + enforcement; the tools themselves are project
deps.** At the end, `install.sh` runs a **detect → offer** pass: it checks for
each tool its configs assume (`ruff`, `pytest`+coverage / `eslint`, `tsc`,
`prettier`, `vitest`) and, for anything missing, offers to install it. The
auto-install only runs when it's **safe** — an interactive terminal, not
`--no-verify`, not inside CI (`$CI`), and not `--no-install`. In any other
non-interactive context it falls back to just printing the command, so CI
and piped/scripted runs never mutate your `package.json` or environment.
Outside CI, point `SCAFFOLD_VERIFY_TTY` at a file of canned replies (one
per prompt, in prompt order, e.g. `y`/`n` lines) to answer those prompts
without a real terminal, for a scripted install that still wants a per-tool
yes/no; `$CI` being set overrides it back to print-only. The package
manager is detected from your lockfiles (`npm`/`pnpm`/`yarn`, `pip`/`uv`).

To install the linters by hand instead:

```sh
pip install ruff pytest pytest-cov  # Python
npm i -D eslint @eslint/js @eslint/compat typescript-eslint eslint-plugin-import-x eslint-plugin-unused-imports typescript prettier vitest @vitest/coverage-v8  # TS/JS
```

### Already have commit history? Scan it once for secrets

`check-secrets` (always on) and `gitleaks.yml` (opt in, see below) only ever look at commits made **after** you install this scaffold. If this repo already has history from before today, an old leaked credential sitting in an earlier commit is invisible to every check above: a clean install does not mean "my repo is safe now" for anything that was already committed.

Run a one-time full-history scan:

```sh
gitleaks git .   # or trufflehog's history mode, e.g. `trufflehog git file://.`
```

If it finds something, **rotate or revoke that credential first**: that is the actual fix, and it's something you can do alone right now. Treat rewriting history (`git-filter-repo` or BFG Repo-Cleaner; never `git filter-branch`, deprecated by Git itself) as optional cleanup afterward, not a substitute for rotation: it force-pushes and rewrites every existing clone, which is exactly the kind of change `AGENTS.md`'s git-discipline rules ask an agent to route through a human rather than do on its own. A first scan on an old repo can also turn up false positives, so treat a hit as "go rotate that credential," not "the repo is broken."

### More secret-scanning layers: push protection and gitleaks

`check-secrets` (the always-on hook and CI check) is a narrow, offline regex gate over the specific token shapes in `.forbidden-patterns/secrets.txt`, not a full secret-scanning boundary: it's the fast net that catches the shapes already known. Two more layers exist, worth knowing about even though only one is opt-in in this scaffold:

- **GitHub push protection** is the zero-effort layer: free and already on by default for a public repo (it blocks a push containing a well-known secret pattern before it lands), no install, no flag, nothing to configure beyond confirming it's on in your repo's Settings > Code security and analysis. Private and internal repos need the paid GitHub Secret Protection add-on to get it; `--gitleaks-ci` below is the free equivalent there.
- **gitleaks** is the broad entropy-plus-~150-rule backstop `check-secrets` defers to. `./install.sh --gitleaks-hook` adds a local pre-commit pass; `./install.sh --gitleaks-ci` adds the unskippable CI gate, which is the actual authoritative boundary (the local pass fails open when the binary isn't installed; CI never does). See [Opt-in layers](./TECHNICAL.md#opt-in-layers) in TECHNICAL.md for the full detail on both.

### Pairing with Husky / lefthook

If your project already uses Husky or lefthook, `install.sh` detects the existing `core.hooksPath` and won't overwrite it. Two ways forward:

1. **Switch to `.githooks`** — point `core.hooksPath` at `.githooks` and migrate any existing hooks into it. Simplest if your existing hooks are minimal.
2. **Chain** — keep your existing tool and have it invoke the scaffold hook as a step. Husky example:
   ```sh
   # .husky/pre-commit
   .githooks/pre-commit
   ```

Either way, the `lib/check-*` scripts in `.githooks/lib/` are also runnable directly. They read a **NUL-separated** file list on stdin (`git ls-files -z | .githooks/lib/check-secrets`), not newline-separated; a plain `git ls-files |` pipe (no `-z`) silently scans nothing. So you can wire them into any orchestrator.

## AI agent integration

The scaffold follows the cross-tool **`AGENTS.md` standard** ([agents.md](https://agents.md)) — a single file at the project root that multiple agents already read (Cursor, Aider, Codex, and others). For tools that read a different filename, `install.sh` or a one-line pointer handles it:

- **Cursor** — reads `AGENTS.md` natively. Nothing else needed.
- **Claude Code** — reads `CLAUDE.md`. `install.sh` drops a `CLAUDE.md` whose `@AGENTS.md` and `@coding-rules.md` imports pull both files into context at session start (`operational-rules.md` stays a link, read on demand: it's too large to pin into every turn).
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
- **Cursor:** create `.cursor/rules/rules.mdc` (or use the command palette's "New Cursor Rule") with the frontmatter `alwaysApply: true` and one line under it: `Follow the rules in operational-rules.md and coding-rules.md.` The root-level `.cursorrules` file older guides point to is [legacy and will be deprecated](https://cursor.com/help/customization/rules).
- **Aider / Cline / etc.**: add the filename(s) to whatever config the tool reads every session (`.aider.conf.yml`, `.clinerules`).

No `install.sh`, no hooks, no CI — the docs are useful in isolation. The full scaffold layers on the enforcement (commit hooks + CI mirror) that turns the rules into machine-checkable failures.

### Scaling context across a large codebase

Root-level `AGENTS.md` is reread on every turn, so its token cost is paid for every prompt. For codebases over ~50 files, drop a nested `AGENTS.md` in each major directory (`app/api/`, `app/web/`, `lib/`) with area-specific gotchas — the standard specifies closest-file-wins, so agents read the nearest one walking up from the file being edited, keeping root-level context small and area context relevant. For Claude Code, a nested `CLAUDE.md` works the same way.

For parallel agent sessions, use `git worktree add ../proj-feat-x -b feat-x` so each session has an isolated working tree on its own branch. Two agents in the same checkout will overwrite each other.

## Verify it works

After install, confirm the hook rejects bad code:

```sh
echo 'print("test")' >> some_module.py
git add some_module.py
git commit -m "should be rejected"
# → hook prints: ✗ some_module.py: Use structlog (or the project's logger), not print()
```

Want to confirm the guardrails are actually wired up, not just present? `scaffold-doctor.sh` is not installed into your project, so run `npx ai-coding-rules-scaffold doctor` from inside your project (works no matter how you installed); or, if you have a git clone of this scaffold repo, run `<path to that clone>/scaffold-doctor.sh` with your project as the working directory. See [Check whether it's armed](./TECHNICAL.md#check-whether-its-armed) in TECHNICAL.md for what it checks.

## Platform notes

- **macOS / Linux:** first-class.
- **Windows:** use Git Bash or WSL. The pre-commit hook is `bash`; Git Bash (bundled with Git for Windows) runs it fine. `chmod +x` is a no-op on NTFS, but Git for Windows treats shell scripts in `.githooks/` as executable regardless.

## License

MIT — see [LICENSE](LICENSE).
