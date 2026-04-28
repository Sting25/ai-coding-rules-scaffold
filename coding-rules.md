# Coding rules

Short rule set. Most discipline is enforced by the linter (`ruff` / `eslint`) and the pre-commit hook — those fail the build or the commit. The rules below are the things that aren't tool-enforceable.

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

## What the tooling enforces

See [README.md](./README.md) > "What the tooling enforces" for the full matrix of build-breaking (`ruff` / `eslint`) and commit-breaking (pre-commit hook + CI) checks. Single source of truth — this doc stays focused on the human-readable rules above.

## Project-specific additions

Each project adds its own tech-specific rules in `coding-rules.md` under a "Project-specific" section (library quirks, import-path conventions, architectural constraints). This scaffold file stays universal.
