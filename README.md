# ai-coding-rules-scaffold

Minimum-viable coding guardrails that prevent unbounded file growth, copy-paste logic, deeply nested control flow, silenced exceptions, and debug leaks in production. Works with any AI coding tool (Claude Code, Cursor, Copilot, Cline, Aider) or no AI at all — enforcement is `ruff` + `eslint` + a pre-commit hook + a CI workflow, all tool-agnostic.

Built for Python/FastAPI + optional TypeScript/React projects. Adapt freely for other stacks.

## Philosophy

**Short doc rule list humans remember + full tool enforcement for the rest.** If the build breaks on `ruff C901`, the fix is forced — no one needs to remember that nested-if depth matters.

The file-size rule (max 500 lines) is the one rule to never raise. Every other rule has tradeoffs in specific cases; unbounded file growth is how projects rot.

Enforcement runs in two places:

- **Pre-commit hook** — blocks the commit locally. Fast feedback, but skippable with `--no-verify`.
- **CI workflow** — blocks the PR server-side. Unskippable. The hook and CI run the same checks.

## Install

Clone the scaffold somewhere stable (the path below is a convention, not a requirement):

```sh
git clone https://github.com/Sting25/ai-coding-rules-scaffold ~/.claude/templates/ai-coding-rules-scaffold
```

From your project root:

```sh
~/.claude/templates/ai-coding-rules-scaffold/install.sh
```

The script auto-detects Python (`pyproject.toml` / `requirements.txt` / `setup.py`) or frontend (`package.json`) and installs the matching pieces. If neither is present, it exits — pass the stack explicitly:

```sh
./install.sh --python       # Python only
./install.sh --frontend     # TS/JS only
./install.sh --both         # both stacks
./install.sh --force        # overwrite existing files
./install.sh --no-verify    # skip the post-install linter check
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
| `coding-rules.md` | `.claude/coding-rules.md` | Short list of rules that aren't tool-enforceable |
| `CLAUDE.md.template` | `CLAUDE.md` | Top-level agent config: git discipline + project section |
| `ruff.toml.template` | `ruff.toml` | Python lint config |
| `eslint.config.js.template` | `eslint.config.js` | TS/JS lint config (flat config, ESLint 9+) |
| `githooks/pre-commit.template` | `.githooks/pre-commit` | File-size + forbidden-patterns check |
| `.github/workflows/lint.yml.template` | `.github/workflows/lint.yml` | CI mirror of the hook |
| `forbidden-patterns/backend.txt.template` | `.forbidden-patterns/backend.txt` | Python patterns consumed by hook + CI |
| `forbidden-patterns/frontend.txt.template` | `.forbidden-patterns/frontend.txt` | TS/JS patterns consumed by hook + CI |

Scripts (live only in the scaffold repo):

| Script | Purpose |
|---|---|
| `install.sh` | Copy templates into your project, wire `core.hooksPath` |
| `uninstall.sh` | Remove unmodified scaffold files, unwire the hook |

## AI agent integration

`install.sh` drops a ready-to-edit `CLAUDE.md` at your project root. If you use a different agent, point it at the same rules.

**Claude Code** — `CLAUDE.md` ships covering git discipline (no amend, no force-push, no `--no-verify`), commit format, and a `Project` section for you to fill in. The rules doc is referenced from there.

**Cursor** — create `.cursorrules` at project root:
```
Follow the rules in .claude/coding-rules.md.
Lint config: ruff.toml (Python), eslint.config.js (TS/JS).
Pre-commit hook enforces file-size ceiling and forbidden patterns — do not bypass with --no-verify.
```

**Cline** — `.clinerules` at project root; same content as `.cursorrules`.

**Aider** — add to `.aider.conf.yml`:
```yaml
read:
  - .claude/coding-rules.md
  - CLAUDE.md
```

**Continue / Copilot / other** — point the tool at `.claude/coding-rules.md` via whatever mechanism it supports.

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
| `print()` in Python files | regex |
| `console.log` / `debugger` / `alert` in TS/JS | regex |
| File size > 500 lines | `wc -l` per staged file |
| TODO/FIXME without ticket ref | regex (opt-in; commented in template) |

## Verify it works

After install, confirm the hook rejects bad code:

```sh
echo 'print("test")' >> some_module.py
git add some_module.py
git commit -m "should be rejected"
# → hook prints: ✗ some_module.py: Use structlog (or the project's logger), not print()
```

## Customize per project

- **`coding-rules.md`** — minimal on purpose. Add a "Project-specific" section at the bottom for stack rules (SQLAlchemy column quirks, import conventions, architectural constraints).
- **`.forbidden-patterns/*.txt`** — simple `regex|description` lines. Add deprecated import paths, old service names, etc. Lines starting with `#` are comments; an opt-in TODO/FIXME pattern is pre-seeded as a comment.
- **`ruff.toml`** — opinionated set (`E,F,I,W,B,UP,SIM,PTH,ANN,BLE,C90,PL,PT,RUF`). Trim `ignore = [...]` if a rule fights your style.
- **Pre-commit hook** — `MAX_LINES=500` by default. Override per-invocation: `MAX_LINES=800 git commit`. Edit the hook to change permanently. The CI workflow reads the same env var.

## Update & uninstall

**Update:** the project's configs are local forks of the templates — `install.sh --force` will overwrite them, including any edits you've made. Diff first:

```sh
diff ~/.claude/templates/ai-coding-rules-scaffold/ruff.toml.template ruff.toml
# merge in the changes you want; leave your customizations
```

For the git repo itself, a `git pull` in the scaffold clone picks up new rules / patterns.

**Uninstall:**

```sh
~/.claude/templates/ai-coding-rules-scaffold/uninstall.sh            # safe: only unmodified files
~/.claude/templates/ai-coding-rules-scaffold/uninstall.sh --dry-run  # preview
~/.claude/templates/ai-coding-rules-scaffold/uninstall.sh --all      # also nuke CLAUDE.md, coding-rules.md, patterns
```

Safe mode only removes files whose content matches the current scaffold template byte-for-byte, so local edits are never lost. `CLAUDE.md`, `.claude/coding-rules.md`, and `.forbidden-patterns/` are kept unless you pass `--all`.

## Platform notes

- **macOS / Linux:** first-class.
- **Windows:** use Git Bash or WSL. The pre-commit hook is `bash`; Git Bash (bundled with Git for Windows) runs it fine. `chmod +x` is a no-op on NTFS but Git for Windows treats shell scripts in `.githooks/` as executable regardless.

## What this scaffold deliberately omits

| Concern | Where it lives instead |
|---|---|
| Architecture / module boundaries | Your project spec or design doc |
| Framework-specific rules (React Query, specific import paths) | `.claude/coding-rules.md` "Project-specific" section |
| Test coverage thresholds, logging conventions | Per-project decision |
| Formatter enforcement (`ruff format`, `prettier`) | Drop-in if you want; the scaffold stays opinion-light here |

## Using this without an AI

The scaffold works fine without any AI tool. Drop the files in, run the hook — same enforcement. The `.claude/coding-rules.md` doc is just a named place to put the rules humans should read. Rename or relocate if that name bothers you.

## License

MIT — see [LICENSE](LICENSE).
