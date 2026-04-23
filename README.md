# coding-rules-scaffold

Minimum-viable coding guardrails that prevent unbounded file growth, copy-paste logic, deeply nested control flow, silenced exceptions, and debug leaks in production. Works with any AI coding tool (Claude Code, Cursor, Copilot, Cline, Aider) or no AI at all — the enforcement layer is `ruff` + `eslint` + a pre-commit hook, all tool-agnostic.

Built for Python/FastAPI + optional TypeScript/React projects. Adapt freely for other stacks.

## Philosophy

**Short doc rule list humans remember** + **full tool enforcement for the rest**. If the build breaks on `ruff C901`, the fix is forced — no one needs to remember that nested-if depth matters.

The file-size rule (max 500 lines) is the one rule to never raise. Every other rule has tradeoffs in specific cases; unbounded file growth is how projects rot.

## Get the scaffold

```sh
git clone https://github.com/Sting25/coding-rules-scaffold ~/.claude/templates/coding-rules-scaffold
```

You can clone anywhere; `~/.claude/templates/` is a convention, not a requirement.

## Install into a project

From your project root:

```sh
~/.claude/templates/coding-rules-scaffold/install.sh
```

The script auto-detects Python (pyproject.toml / requirements.txt / setup.py) or frontend (package.json) and installs the matching pieces. To override:

```sh
./install.sh --python     # Python only
./install.sh --frontend   # TS/JS only
./install.sh --both       # both stacks
./install.sh --force      # overwrite existing files
```

Then install the linters:

```sh
pip install ruff                                   # Python
npm i -D eslint @eslint/js typescript-eslint       # TS/JS
```

Finally, reference the rules from your AI agent config. For Claude Code, add to `.claude/CLAUDE.md`:

```markdown
## Coding rules
See `.claude/coding-rules.md` and `ruff.toml`. Tool-enforced on every commit via `.githooks/pre-commit`.
```

For Cursor / Cline / Aider / etc., reference `.claude/coding-rules.md` from whatever config file the tool uses.

## What's in the scaffold

| File | Goes to | Purpose |
|---|---|---|
| `coding-rules.md` | `<project>/.claude/coding-rules.md` | Short list of rules that aren't tool-enforceable |
| `ruff.toml.template` | `<project>/ruff.toml` | Python lint config |
| `eslint.config.js.template` | `<project>/eslint.config.js` | TS/JS lint config (flat config, ESLint 9+) |
| `githooks/pre-commit.template` | `<project>/.githooks/pre-commit` | Shell script: file-size + forbidden-patterns check |
| `forbidden-patterns/backend.txt.template` | `<project>/.forbidden-patterns/backend.txt` | Python-side patterns consumed by the hook |
| `forbidden-patterns/frontend.txt.template` | `<project>/.forbidden-patterns/frontend.txt` | TS/JS patterns consumed by the hook |
| `install.sh` | — | One-command installer (you run this) |

## Verify the hook works

After install, trigger it to confirm:

```sh
# Add 'print("test")' to a .py file, stage it, try to commit.
# The hook should reject the commit with a pointer to the backend.txt pattern.
```

## Customize per project

- **`coding-rules.md`** — minimal on purpose. Add a "Project-specific" section at the bottom for tech-stack rules (SQLAlchemy column quirks, specific library imports, architectural constraints). The scaffold file stays universal.
- **`.forbidden-patterns/*.txt`** — simple `regex|description` lines. Add project-specific forbidden strings (deprecated import paths, old service names, etc.).
- **`ruff.toml`** — opinionated rule set (`E,F,I,W,B,UP,SIM,PTH,ANN,BLE,C90,PL,PT,RUF`). Trim in `ignore = [...]` if specific rules conflict with your style.
- **Pre-commit hook** — uses `MAX_LINES=500` by default. Override with `MAX_LINES=N git commit` or edit the hook.

## What this scaffold deliberately omits

| Concern | Where it lives instead |
|---|---|
| Commit message format, amend/force-push/push discipline | Your AI agent config (CLAUDE.md etc.) |
| Architecture / module boundaries | Your project spec or design doc |
| Framework-specific rules (React Query, specific import paths) | Project's `.claude/coding-rules.md` "Project-specific" section |
| Test coverage thresholds, verbose logging conventions | Per-project decision |

## Using this without an AI

The scaffold works fine without any AI tool. Drop the files into a project, run the hook — same enforcement. The `.claude/coding-rules.md` doc is just a named place to put the rules humans should read. Rename or relocate if that name bothers you.

## License

MIT — see [LICENSE](LICENSE).
