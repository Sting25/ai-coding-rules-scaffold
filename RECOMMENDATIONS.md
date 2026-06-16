# Recommendations

Things this scaffold deliberately doesn't do, but might be worth adopting in setups it isn't sized for. Each entry has explicit triggering conditions — adopt only if those apply to you.

## Maintenance

Entries are dated. If one has gone untouched for over a year, delete it (or move it to a GitHub issue with a `future-ideas` label). Active discussion belongs in issues, not here — a stale recommendation is worse than no recommendation.

---

## Agent-runtime hooks (Claude Code `PreToolUse`, Cursor `beforeShellExecution`, Gemini `BeforeTool`)

_Added 2026-04-23. **Minimal version shipped 2026-06-10** — `install.sh --claude` installs a `.claude/settings.json` deny-list plus a `PreToolUse` precheck (`.githooks/lib/agent-precheck`) that scans Write/Edit/Bash content against the same `.forbidden-patterns/secrets.txt` the commit-time scanner uses. **Cursor support added 2026-06-11** — `install.sh --cursor` wires the same precheck to Cursor's `beforeShellExecution` via `.cursor/hooks.json` (shell-command scan only; Cursor has no before-write hook). The full framework below remains out of scope._

**Adopt if:** you have ≥3 concurrent agents, OR CI is rejecting more than ~1 violation/week that the agent could have caught at write-time, OR a single security incident from agent-issued shell commands has happened.

**What it is.** IDE-level hooks fire at the agent's action boundary — *before* the agent edits a file or runs a shell command. Git hooks (this scaffold) fire at the commit boundary, after the agent has already written the code. Different boundary, different class of problem caught:

| Layer | Catches | This scaffold has it? |
|---|---|---|
| Agent hooks (pre-tool-use) | Agent about to exfiltrate a secret, run `curl \| bash`, edit outside scope | Yes — opt-in (`install.sh --claude` / `--cursor`) |
| Linters (`ruff`, `eslint`) | Code quality once code is written | Yes |
| Git pre-commit | Debug leaks, file size, forbidden patterns at commit | Yes |
| CI mirror | All of the above, server-side, unskippable | Yes |

**The minimal version (now shipped).** `install.sh --claude` wires `PreToolUse` to `.githooks/lib/agent-precheck`, which scans the content of a Write/Edit/Bash call against `.forbidden-patterns/secrets.txt` — the same patterns the commit-time `check-secrets` uses. For **Bash** tool calls it additionally scans the command against `.forbidden-patterns/shell.txt` (case-sensitive, matching commit-time semantics) — blocking `curl|bash`, `rm -rf /`, `chmod 777` before the agent runs them, which is the shell-command security scan called out below as the highest-ROI hook. The same rule set runs in three places: agent → commit → CI. The bundled `.claude/settings.json` also denies the agent reading credential files (`.env`, `*.pem`, `~/.ssh/**`, `~/.aws/**`, …) outright, and sets `enableAllProjectMcpServers: false` with an empty `enabledMcpjsonServers` allowlist — so a cloned/forked repo's `.mcp.json` can't auto-approve a source/env-exfiltrating MCP server (CVE-2026-21852).

**The full version (overkill for most).** See [johnclick.ai/blog/hooks-based-enforcement-for-ai-agents](https://johnclick.ai/blog/hooks-based-enforcement-for-ai-agents/). Three-layer pattern (hooks + validators + guard YAMLs), four hook families (compliance / security / quality / orchestration), monitor → warn → enforce gradual rollout. Appropriate for production fleets of 10+ concurrent agents; overkill for small teams.

**Highest-ROI first hook if you only adopt one.** Shell-command security scan in `PreToolUse` — block `curl | bash`, credential patterns, destructive git commands before the agent runs them. Per the source article, this is the single highest-ROI agent hook.

**Why the full framework is still out.** Adopting the full framework (validators + guard YAMLs + four hook families + monitor→warn→enforce rollout) dilutes the scaffold's "minimum-viable guardrails" identity. The minimal version is now shipped opt-in (above); the full framework stays a pointer, not a dependency.

---

## Spec-first workflow templates (`SPEC.md`)

_Added 2026-04-23._

**Adopt if:** team includes junior developers using AI as a senior engineer, OR features regularly land that don't match what was asked for, OR scope creep is the dominant failure mode in code review.

**What it is.** An opt-in `SPEC.md` template at the project root with sections for Problem / Non-goals / Constraints / Acceptance criteria / Open questions. Filled out *before* code starts. Anchors the agent to a defined scope and forces explicit non-goals — the section that catches AI scope creep most reliably.

**Why not in the scaffold.** Spec discipline is project-specific and team-specific. Imposing a template would push the scaffold from "rule enforcement" toward "process opinion," which is a different category of tool.

---

## Language-agnostic forbidden-patterns file

_Added 2026-04-22._

**Mostly superseded (2026-06-10).** The two concrete needs this entry described are now covered without a new pattern file:

- **Git conflict markers** — handled by `.githooks/lib/check-hygiene`, which scans every staged blob for `<<<<<<<` / `|||||||` / `>>>>>>>` markers (and also flags case-only filename collisions).
- **AWS keys / credentials in any text file** — `check-secrets` already scans **every** tracked file's staged blob as text (no extension allowlist), so a key in Markdown / YAML / JSON is caught.

**Still open:** a general-purpose `common.txt` for *project-defined* cross-language deny patterns (e.g. an internal hostname that should never appear in any file type). Held back pending demand — `check-patterns` could gain a `common.txt` consumed across all extensions if a concrete need appears.

---

## `ruff` FURB (refurb) rule group

_Added 2026-06-11._

**Adopt if:** your team wants idiom-level modernization beyond the `UP` / `SIM` / `PTH` groups the scaffold already ships, and is willing to triage FURB's more opinionated rewrites (operator reimplementation, comprehension / `starmap` rewrites, read-whole-file).

**What it is.** `FURB` (flake8-refurb, stabilized in 2025 ruff releases) flags outdated idioms with modern stdlib replacements. It overlaps the deterministic, high-value slice the scaffold's selected `UP`/`SIM`/`PTH` groups already cover; the marginal additions skew toward style preference rather than a new bug class, which is why it's not default-on (it would raise the false-positive / "preachy refactor" rate an expert pushes back on). Add `"FURB"` to `[lint] select` in `ruff.toml` and tune `ignore` per project. `PERF` (perflint) stays out entirely.

---

## Commit-time Python type-check (`ty` / `pyrefly`)

_Added 2026-06-11._

**Adopt if:** `ty` reaches 1.0 stable (0.0.x beta as of mid-2026) **and** type errors are reaching CI more than ~1/week from agent sessions.

**What it is.** `coding-rules.md` rule 9 wires `tsc --noEmit` into the pre-commit hook for TypeScript but defers Python type-checking (`pyright`/`mypy`) to CI because they're too slow for a hook. The Rust-based `ty` / `pyrefly` remove the speed objection (10–60× faster). When `ty` is stable, the hook can gain `ty check` behind the same guard as `tsc` — run only when the binary is on PATH and a config is present, silently skip otherwise, CI stays authoritative. Rule 8's `pyright`/`mypy` remain the conformance reference and stay unchanged. Docs-only until then — no change to any `check-*` script.

---

## Forcing tests (patch coverage + mutation testing)

_Added 2026-06-16. **Patch-coverage gate shipped 2026-06-16** — `install.sh --coverage-gate` installs `.github/workflows/coverage.yml`, a `diff-cover` job that fails a PR when changed lines aren't covered. Mutation testing below remains out of scope._

**Adopt mutation testing if:** a coverage gate is already in place **and** assertion-free / trivially-passing tests are getting through review (a signature agent pattern when coverage is the target).

**What you can and can't machine-force.** You cannot force *meaningful* tests with a build gate — only mechanical proxies, every one gameable, most of all by an agent optimizing to pass the gate. The proxies, weakest to strongest:

- **"source changed ⇒ a test file changed"** — trivially satisfied by touching a test; high false-positive on refactors/docs. Not worth shipping.
- **Whole-repo coverage threshold** (`≥ 80%`) — old untested code masks new gaps. Weak for a scaffold.
- **Patch / diff coverage** (changed lines must be covered) — the strongest *defensible* gate, and what the scaffold ships (`--coverage-gate`). The honest ceiling: it forces changed lines to be **executed** by a test, never **verified** by one. An assertion-free test that just calls the function gives 100% patch coverage.
- **Mutation testing** (`Stryker` for TS/JS, `mutmut` / `cosmic-ray` for Python) — the only tool that measures test *quality*: it injects faults and checks the tests catch them. It closes the assertion-free hole, but it's slow, needs tuning, and still requires tests to exist first. Gate on mutation score for the changed files only.

**Why mutation testing stays deferred.** Default-on mutation testing makes CI minutes-to-tens-of-minutes slower and is flaky on some code shapes — too heavy to impose by default. Wire it as a separate opt-in job (or a nightly run) over the diff, not the whole tree. Until then this is docs-only; the patch-coverage gate plus required human review is the shipped answer to "how do we force tests."

---

## `Biome` / `oxlint` instead of (or in front of) ESLint

_Added 2026-06-11._

**Adopt if:** `npx eslint .` in CI exceeds ~2–3 min, **or** editor feedback is laggy at monorepo scale, **or** the team wants formatter + linter in one tool and accepts weaker typed-rule coverage.

**Why ESLint stays the default.** The shipped `eslint.config.js` exists for its type-aware tier (`no-floating-promises`, `no-misused-promises`, `await-thenable`), and typed rules need real compiler types — which only typescript-eslint covers today. The Rust-based linters are dramatically faster but trade away (most of) that typed coverage. **Re-evaluate when:** the `oxlint` + `eslint-plugin-oxlint` hybrid (fast linter for the untyped bulk, ESLint for typed rules only) or `tsgolint` closes the typed-rule gap.

---

## Pin the CI `ruff` version

_Added 2026-06-11._

**Adopt if:** you depend on hook/CI lint parity being byte-reproducible across runs, or you treat CI PyPI installs as a supply-chain surface.

**What it is.** `lint.yml`'s `pip install ruff` pulls whatever PyPI serves that day, so lint behavior can shift between runs. Pin it: `pip install ruff==X.Y.Z  # bump manually on upgrades`. **Honest caveat:** Dependabot's `pip` ecosystem scans manifests (`requirements`/`pyproject`), **not** a version literal embedded in workflow YAML — so a `ruff==X` pin in `lint.yml` is maintained by hand, or by pinning `ruff` in the project's own `pyproject`/`requirements` and installing from there. (This is the corrected scope of the `SECURITY_AUDIT.md` "ruff/eslint are unshared, unpinned" Low finding.)

---

## SLSA provenance / trusted publishing (npm / PyPI)

_Added 2026-06-11._

**Adopt if:** your repo publishes to npm / PyPI / RubyGems.

**What it is.** Switch the publish workflow to OIDC **trusted publishing** — there is no long-lived registry token to steal or worm-propagate (Shai-Hulud spread specifically by republishing packages with harvested npm tokens). On npm this also auto-signs Sigstore build provenance. Advice-only: the scaffold's primary audience is app teams that never publish a package, and there's no machine check here. npm trusted publishing went GA 2025-07; see npm trusted-publishers docs, PyPI trusted publishers, and the SLSA spec.

---

## Automated SemVer releases from Conventional Commits (release-please)

_Added 2026-06-11._

**Adopt if:** you publish a versioned package or tagged releases **and** already run `install.sh --commit-msg`. Skip for internal deploy-from-`main` services.

**What it is.** `release-please` maintains a release PR that bumps SemVer from your commit types, writes `CHANGELOG.md`, and tags the release — the natural payoff of the Conventional-Commits hook the scaffold already ships opt-in. **Why not in the scaffold:** it adds a third-party action dependency and sits downstream of the scaffold's enforcement boundary. If you adopt it, SHA-pin the action like the existing workflows and let Dependabot bump it.
