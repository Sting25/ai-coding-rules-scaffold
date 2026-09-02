# Coding rules

Short rule set. Most discipline is enforced by the linter (`ruff` / `eslint`) and the pre-commit hook — those fail the build or the commit. The rules below are the things that aren't tool-enforceable.

## File size

1. **Max 500 lines per file.** When approaching the limit, extract a focused module. Never raise the limit.

## Structure

2. **No copy-paste logic** — import existing helpers. Duplication invites drift.
3. **Before creating a new file, check for extension candidates.** Search the codebase for existing modules that could absorb the new logic. When you do create, state in the commit or PR body what you considered and why it couldn't extend.
4. **`asyncio.to_thread()` for blocking I/O** in async paths — never block the event loop. Under the GIL a CPU-bound function moved to a thread still stalls the loop (the CPython `asyncio.to_thread` docs call this out), so CPU-bound work belongs in a process pool (`loop.run_in_executor` with a `ProcessPoolExecutor`); free-threaded 3.13t+/3.14 builds are the exception. _(TypeScript)_ Never leave a promise floating — `await` it or handle it explicitly.

## Pattern files

Stack-specific deny patterns live in `.forbidden-patterns/*.txt` — one per language, plus the language-agnostic `secrets.txt`. Add deprecated import paths, old service names, banned API keys, etc.; the hook scans them on every commit and so does CI. Format is `<regex><TAB><description>` per line; each file declares the extensions it scans with a `# scaffold-extensions:` header, so adding a language is just dropping a file. See `forbidden-patterns/README.md` in the scaffold repo for the full reference.

## Communication

5. **Cite `file:line` when flagging an issue.** "The config is wrong" is vague; "`config.py:43` is wrong because…" is actionable. Applies to code review, bug reports, memory entries, and mid-task observations.

## Testing

6. **Four-category baseline**, picked per stack. Every project ships with all four:
   - **Linter/formatter** — catches sloppy edits before commit
   - **Type-checker** — catches contract drift before runtime
   - **Test runner** — unit + integration tests
   - **Property-based** — edge cases the human writer didn't think of, especially in numeric / spatial / parsing code

   Defaults: Python — `ruff`, `pyright`/`mypy`, `pytest`, `hypothesis`. TypeScript — `eslint`+`prettier`, `tsc`, `vitest`/`jest`, `fast-check`. New stacks pick equivalents and document the choice in the project's `AGENTS.md`.

   **A test you have never watched fail is not evidence.** Write it before the change, or run it against the base commit — a test written against code that already exists passes by construction; a new test that legitimately passes on base (characterization before a refactor, coverage backfill) must say so and why. Never delete a test in the same change as the code it covered, and never delete, skip, or loosen a test to turn a build green — see `AGENTS.md` > "Checks" and "Fix the file, not the guardrail" in `operational-rules.md`. `install.sh --test-guard` adds the red-green half of this as an opt-in CI gate.

7. **The pre-commit hook is the gate.** It runs the size/pattern/secret guards plus the linter (`ruff` / `eslint`), and — for TypeScript — `tsc --noEmit` whenever a `tsconfig.json` is present. Wire the rest of your type-checker (`pyright` / `mypy`) into CI per the project's `AGENTS.md`. For when skipping the hook (`--no-verify`) is and is not legitimate, `AGENTS.md` > "Git discipline" is the single authority.

## Observability

8. **Structured logging library**, picked per stack. Output JSON, not plain text — downstream tools (alerting, dashboards, log search) all depend on parseable structure, so pass fields as arguments rather than formatting them into the message string. Defaults: Python — `structlog`. TypeScript — `pino` or `winston`. New stacks pick equivalents.

9. **Event names are `snake_case_verbs`**, not prose. Example: `request_received`, `cog_written`, `gpu_lock_acquired`. They must be filterable strings — log handlers, alerting rules, and grep all depend on stable identifiers. Prose like "the request came in fine" is not a log event name.

10. **Bind a request correlation ID to log context** when running multiple services. Prefer the W3C `traceparent` header (`X-Request-Id` is an acceptable lighter-weight fallback). Either way: echo incoming, generate if missing, bind to log context — every log line in the request then carries the same ID, so a single grep finds the full cross-service trace.

## Versioning

11. **Stable-additive only.** Adding new fields, files, endpoints, or columns is free and doesn't require coordination. Renaming, removing, or changing the type of existing fields requires: (a) a schema-version bump, (b) explicit notice to consumers before the change ships, (c) a deprecation window when feasible. Silent breaking changes are the most expensive kind because they fail downstream, far from the cause.

## Dependencies

12. **Before adding an external package, verify it is the package you think it is.** Rule 3's instinct, one layer out: prefer a library the project already depends on, then the standard library, and only then something new. When a new dependency is genuinely needed, check it on the registry _before_ the name reaches a manifest or a lockfile. Does the name resolve at all? Is it the well-known project you had in mind, rather than a near-miss spelling, a scoped look-alike, or a same-named package published last month? Do its version history, download history, and listed source repository match the project you meant? AI tools invent plausible-but-nonexistent package names, and attackers pre-register the invented names to catch the install ("slopsquatting"), so a package that installs cleanly is not evidence that it is real — dependency scanners match known-bad packages, and a freshly registered plausible name is by construction not in them yet. State in the commit or PR body which package you chose and what you checked.

## Git

See `AGENTS.md` for commit format and Git discipline (no amend, no force-push, no push unless asked, no hook bypass).

## What the tooling enforces

See [TECHNICAL.md > "What the tooling enforces"](https://github.com/Sting25/ai-coding-rules-scaffold/blob/main/TECHNICAL.md#what-the-tooling-enforces) for the full matrix of build-breaking (`ruff` / `eslint`) and commit-breaking (pre-commit hook + CI) checks. Single source of truth: this doc stays focused on the human-readable rules above.

## Project-specific additions

Each project adds its own tech-specific rules here, under a "Project-specific" heading (library quirks, import-path conventions, architectural constraints). This scaffold file stays universal. The two below are worked examples of the shape — keep the ones your stack uses, delete the rest:

- **FastAPI endpoints return Pydantic response models**, not raw dicts. Applies if the project uses FastAPI.
- **SQLAlchemy 2.0 style only** (`Mapped[]`, `mapped_column()`). No `declarative_base` or pre-2.0 patterns. Applies if the project uses SQLAlchemy.
