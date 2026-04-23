# Coding rules

Minimum rule set. Most discipline is enforced by the linter (`ruff` / `eslint`) and the pre-commit hook — those fail the build or the commit. The rules below are the things that aren't tool-enforceable.

## File size

1. **Max 500 lines per file.** When approaching the limit, extract a focused module. Never raise the limit.

## Structure

2. **No copy-paste logic** — import existing helpers. Duplication invites drift.
3. **Before creating a new file, check for extension candidates.** Search the codebase for existing modules that could absorb the new logic. When you do create, state in the commit or PR body what you considered and why it couldn't extend.
4. **FastAPI endpoints return Pydantic response models**, not raw dicts. Applies if the project uses FastAPI.
5. **SQLAlchemy 2.0 style only** (`Mapped[]`, `mapped_column()`). No `declarative_base` or pre-2.0 patterns. Applies if the project uses SQLAlchemy.
6. **`asyncio.to_thread()` for blocking CPU work** in async paths. Never block the event loop.

## Communication

7. **Cite `file:line` when flagging an issue.** "The config is wrong" is vague; "`config.py:43` is wrong because…" is actionable. Applies to code review, bug reports, memory entries, and mid-task observations.

## Git

See `AGENTS.md` for commit format and Git discipline (no amend, no force-push, no push unless asked).

## What the tooling enforces (for reference)

Build-breaking (`ruff` / `eslint`):

| Concern | Tool rule |
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

Commit-breaking (pre-commit hook):

| Concern | Check |
|---|---|
| `print()` in Python files | regex |
| `console.log` in TS/JS files | regex |
| File size > 500 lines | `wc -l` per staged file |

## Project-specific additions

Each project adds its own tech-specific rules in `coding-rules.md` under a "Project-specific" section (library quirks, import-path conventions, architectural constraints). This scaffold file stays universal.
