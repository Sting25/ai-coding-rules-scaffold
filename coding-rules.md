# Coding rules

Rules about the code that tools cannot enforce; the linter (`ruff` / `eslint`) and the pre-commit hook fail the build or the commit on the rest. Git and collaboration rules live in `AGENTS.md` and `operational-rules.md`.

## File size

1. **Max 500 lines per file.** When approaching the limit, extract a focused module. Never raise the limit.

## Structure

2. **No copy-paste logic.** Import existing helpers; duplication drifts.
3. **Before creating a new file, check for extension candidates.** Search for an existing module that could absorb the logic. When you do create one, state in the commit or PR body what you considered and why it could not extend.
4. **Never block the event loop.** Blocking I/O in async code goes through `asyncio.to_thread()`; CPU-bound work goes to a process pool (`loop.run_in_executor` with a `ProcessPoolExecutor`), because under the GIL a thread still stalls the loop (free-threaded 3.13t+ builds excepted). _(TypeScript)_ Never leave a promise floating: `await` it or handle it explicitly.

## Pattern files

Stack-specific deny patterns live in `.forbidden-patterns/*.txt`, one per language plus `secrets.txt`; the hook and CI scan them on every commit. Add deprecated import paths, old service names, and the like. Format reference: the scaffold's `forbidden-patterns/README.md`.

## Communication

5. **Cite `file:line` when flagging an issue**: "`config.py:43` is wrong because..." rather than "the config is wrong". Applies to reviews, bug reports, notes, and mid-task observations.

## Testing

6. **Four-category baseline**, picked per stack: a linter/formatter, a type-checker, a test runner (unit and integration), and property-based tests for the edge cases nobody thought of (especially numeric, spatial, and parsing code). Defaults: Python `ruff`, `pyright`/`mypy`, `pytest`, `hypothesis`; TypeScript `eslint`+`prettier`, `tsc`, `vitest`/`jest`, `fast-check`. Other stacks pick equivalents and record them in `AGENTS.md`.

   **A test you have never watched fail is not evidence.** Write it before the change, or run it against the base commit; a test written against existing code passes by construction. A new test that legitimately passes on base (characterization before a refactor, coverage backfill) says so and why. `install.sh --test-guard` adds this as an opt-in CI gate.

   **Assert the positive outcome**, not only the absence of a symptom: pair each "the error is absent" with "the wanted artifact was produced" (marker emitted, exit 0, file present), because a crash also makes the error absent.

   **Integration tests hit a real database**, an ephemeral one per run if isolation matters, never a mock connection. Run pre-production checks in an environment built by the same provisioning as production.

7. **The pre-commit hook is the gate.** It runs the size, pattern, and secret guards, the linter, and `tsc --noEmit` when a `tsconfig.json` exists. Wire the rest of the type-checking (`pyright` / `mypy`) into CI. `AGENTS.md` > "Git discipline" is the only authority on `--no-verify`.

## Observability

8. **Structured logging library**, picked per stack (Python `structlog`; TypeScript `pino` or `winston`). Output JSON, and pass fields as arguments rather than formatting them into the message.

9. **Event names are `snake_case_verbs`**, not prose: `request_received`, `job_completed`, `cache_miss`. Filters, alerts, and grep depend on stable identifiers.

10. **Bind a request correlation ID to log context** when running multiple services. Prefer the W3C `traceparent` header (`X-Request-Id` is an acceptable fallback): echo it, generate it if missing, bind it, so one grep finds the whole trace.

## Versioning

11. **Stable-additive only.** Adding fields, files, endpoints, or columns is free. Renaming, removing, or retyping an existing one requires a schema-version bump, notice to consumers before it ships, and a deprecation window when feasible.

## Dependencies

12. **Before adding an external package, verify it is the package you think it is.** Prefer a library the project already uses, then the standard library, then something new. Check a new name on the registry before it reaches a manifest or lockfile: does it resolve, is it the well-known project rather than a near-miss spelling, a scoped look-alike, or a recent namesake, and do its versions, downloads, and source repository match? AI tools invent plausible names and attackers register them ("slopsquatting"), so a clean install proves nothing. State in the commit or PR body which package you chose and what you checked.

## Data and failure handling

13. **Validate inputs at component boundaries.** Never assume the upstream component honored the contract. Type annotations document structure but do not enforce it, so tests assert the type and also touch the named fields.

14. **Read schema constraints before writing data.** Open the model and its enum and check constraints before composing an INSERT, UPDATE, or migration; plausible-looking values often violate constraints you did not see.

15. **No silent failures.** When a unit of work fails (a request, a record, a job), log a WARN-or-higher event with the reason and surface the failure in the response: a `partial` status, an error field, a non-success code. Never report success over a swallowed error.

## Project-specific additions

Add your project's own rules here (library quirks, import-path conventions, architectural constraints). Two examples of the shape; keep the ones your stack uses:

- **FastAPI endpoints return Pydantic response models**, not raw dicts.
- **SQLAlchemy 2.0 style only** (`Mapped[]`, `mapped_column()`); no `declarative_base`.
