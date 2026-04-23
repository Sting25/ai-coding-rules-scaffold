# ai-coding-rules-scaffold

[![Latest release](https://img.shields.io/github/v/release/Sting25/ai-coding-rules-scaffold)](https://github.com/Sting25/ai-coding-rules-scaffold/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Opinionated coding guardrails that prevent unbounded file growth, deeply nested control flow, silenced exceptions, debug leaks (`print`, `console.log`, `breakpoint`, `pdb`), hardcoded secrets/tokens, and stray `.env` or private-key files. Agent-agnostic: works with Cursor, Claude Code, Copilot, Cline, Aider, or no AI at all — enforcement is `ruff` + `eslint` + a pre-commit hook + a CI mirror that runs the same checks server-side so `--no-verify` doesn't become the escape hatch.

Built for Python/FastAPI + optional TypeScript/React projects. Adapt freely for other stacks.

## Philosophy

**Short doc rule list humans remember + full tool enforcement for the rest.** If the build breaks on `ruff C901`, the fix is forced — no one needs to remember that nested-if depth matters.

The file-size rule (max 500 lines) is the one rule to never raise. Every other rule has tradeoffs in specific cases; unbounded file growth is how projects rot.

Enforcement runs in two places:

- **Pre-commit hook** — blocks the commit locally. Fast feedback, skippable with `--no-verify`.
- **CI workflow** — blocks the PR server-side. Unskippable. The hook and CI run the same checks.

## Install

Clone the scaffold somewhere stable:

```sh
git clone https://github.com/Sting25/ai-coding-rules-scaffold ~/src/ai-coding-rules-scaffold
# Or pin to a specific release:
git clone --branch v0.2.0 https://github.com/Sting25/ai-coding-rules-scaffold ~/src/ai-coding-rules-scaffold
```

From your project root:

```sh
~/src/ai-coding-rules-scaffold/install.sh
```

The script auto-detects Python (`pyproject.toml` / `requirements.txt` / `setup.py`) or frontend (`package.json`) and installs the matching pieces. If neither is present, it exits — pass the stack explicitly:

```sh
./install.sh --python       # Python only
./install.sh --frontend     # TS/JS only
./install.sh --both         # both stacks
./install.sh --force        # overwrite existing files
./install.sh --no-verify    # skip the post-install linter check
./install.sh --help         # show usage
```

At the end, `install.sh` verifies that `ruff` and/or `eslint` are installed and that their configs load. If either is missing, it prints the install command.

Install the linters:

```sh
pip install ruff                                   # Python
npm i -D eslint @eslint/js typescript-eslint       # TS/JS
```

## What lands in your project

| Scaffold file | Installed as | Purpose |
|---|---|---|
| `AGENTS.md.template` | `AGENTS.md` | Primary agent doc: git discipline + project section |
| `CLAUDE.md.pointer` | `CLAUDE.md` | One-liner pointing Claude Code at `AGENTS.md` |
| `coding-rules.md` | `coding-rules.md` | Short list of rules that aren't tool-enforceable |
| `ruff.toml.template` | `ruff.toml` | Python lint config |
| `eslint.config.js.template` | `eslint.config.js` | TS/JS lint config (flat config, ESLint 9+) |
| `githooks/pre-commit.template` | `.githooks/pre-commit` | File-size, forbidden-patterns, secrets, and blocked-filenames check |
| `.github/workflows/lint.yml.template` | `.github/workflows/lint.yml` | CI mirror of the hook |
| `forbidden-patterns/backend.txt.template` | `.forbidden-patterns/backend.txt` | Python patterns consumed by hook + CI |
| `forbidden-patterns/frontend.txt.template` | `.forbidden-patterns/frontend.txt` | TS/JS patterns consumed by hook + CI |
| `forbidden-patterns/secrets.txt.template` | `.forbidden-patterns/secrets.txt` | Secret/credential patterns, scanned across all file types |

Scripts (stay in the scaffold repo):

| Script | Purpose |
|---|---|
| `install.sh` | Copy templates into your project, wire `core.hooksPath`, verify linters |
| `uninstall.sh` | Remove unmodified scaffold files, unwire the hook |

## AI agent integration

The scaffold follows the cross-tool **`AGENTS.md` convention** — a single file at the project root that multiple agents already read (Cursor, Aider, and others). For tools that read a different filename, `install.sh` or a one-line pointer handles it:

- **Cursor** — reads `AGENTS.md` natively. Nothing else needed.
- **Claude Code** — reads `CLAUDE.md`. `install.sh` drops a one-line `CLAUDE.md` containing `@AGENTS.md`, which pulls `AGENTS.md` into context.
- **Aider** — add to `.aider.conf.yml`:
  ```yaml
  read:
    - AGENTS.md
    - coding-rules.md
  ```
- **Cline** — create `.clinerules` with one line:
  ```
  Follow the rules in AGENTS.md and coding-rules.md.
  ```
- **Continue / Copilot / other** — point the tool at `AGENTS.md` via whatever config it supports.

## What the tooling enforces

Build-breaking (`ruff` / `eslint`, on every lint + in CI):

| Concern | Rule |
|---|---|
| Nested control flow > 3 deep | `ruff C901`, `eslint max-depth: 3` |
| Cyclomatic complexity > 10 | `ruff C901`, `eslint complexity: 10` |
| `os.path.join` / string path math | `ruff PTH100-208` |
| Blind `except Exception: pass` | `ruff BLE001` |
| Missing public-API return types | `ruff ANN201` |
| Function > 60 lines | `ruff PLR0915` |
| Too many branches / statements | `ruff PLR0912`, `PLR0915` |
| Line length > 100 | `ruff E501` |
| Unsorted / unused imports | `ruff I`, `F401` |
| `any` in TypeScript without comment | `@typescript-eslint/no-explicit-any` |

Commit + CI-breaking (pre-commit hook + `lint.yml`):

| Concern | Check |
|---|---|
| `print()`, `breakpoint()`, `pdb.set_trace()`, `ipdb.set_trace()` in Python files | regex |
| `console.log` / `debugger` / `alert` in TS/JS | regex |
| File size > 500 lines | `wc -l` per staged file |
| TODO/FIXME without ticket ref | regex (opt-in; commented in template) |
| Secret / credential leaks (AWS keys, GitHub tokens, private keys, URLs with embedded credentials, hardcoded password=/token= assignments) | regex (case-insensitive, all files) |
| Committed `.env` / `*.pem` / SSH private keys (`id_rsa`, `id_ed25519`, `id_ecdsa`, `id_dsa`) | filename check (`.env.example` / `.env.sample` / `.env.template` allowed) |

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
- **`.forbidden-patterns/*.txt`** — simple `regex|description` lines. Add deprecated import paths, old service names, etc. Lines starting with `#` are comments; an opt-in TODO/FIXME pattern is pre-seeded as a comment.
- **`ruff.toml`** — opinionated set (`E,F,I,W,B,UP,SIM,PTH,ANN,BLE,C90,PL,PT,RUF`). Trim `ignore = [...]` if a rule fights your style.
- **Pre-commit hook** — `MAX_LINES=500` by default. Override per-invocation: `MAX_LINES=800 git commit`. Edit the hook to change permanently. The CI workflow reads the same env var.
- **Adopting on an existing codebase** — the CI size check runs against *all* tracked source files, not just changed ones. If the repo already has files over 500 lines, the first PR will fail. Either extract the offenders first (preferred — this is the debt the rule is meant to catch) or set `MAX_LINES` higher temporarily in both the hook and CI, then ratchet it down as you refactor.

## Update & uninstall

**Update:** the project's configs are local forks of the templates. `install.sh --force` overwrites them, including any edits. Diff first:

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
| Test coverage thresholds, logging conventions | Per-project decision |
| Formatter enforcement (`ruff format`, `prettier`) | Drop-in if you want; the scaffold stays opinion-light here |

## Using this without an AI

The scaffold works fine without any AI tool. Drop the files in, run the hook — same enforcement. `coding-rules.md` is just a named place to put the rules humans should read.

## License

MIT — see [LICENSE](LICENSE).
