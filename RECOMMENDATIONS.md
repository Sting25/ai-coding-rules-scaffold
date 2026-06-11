# Recommendations

Things this scaffold deliberately doesn't do, but might be worth adopting in setups it isn't sized for. Each entry has explicit triggering conditions — adopt only if those apply to you.

## Maintenance

Entries are dated. If one has gone untouched for over a year, delete it (or move it to a GitHub issue with a `future-ideas` label). Active discussion belongs in issues, not here — a stale recommendation is worse than no recommendation.

---

## Agent-runtime hooks (Claude Code `PreToolUse`, Cursor `beforeShellExecution`, Gemini `BeforeTool`)

_Added 2026-04-23. **Minimal version shipped 2026-06-10** — `install.sh --claude` installs a `.claude/settings.json` deny-list plus a `PreToolUse` precheck (`.githooks/lib/agent-precheck`) that scans Write/Edit/Bash content against the same `.forbidden-patterns/secrets.txt` the commit-time scanner uses. The full framework below remains out of scope._

**Adopt if:** you have ≥3 concurrent agents, OR CI is rejecting more than ~1 violation/week that the agent could have caught at write-time, OR a single security incident from agent-issued shell commands has happened.

**What it is.** IDE-level hooks fire at the agent's action boundary — *before* the agent edits a file or runs a shell command. Git hooks (this scaffold) fire at the commit boundary, after the agent has already written the code. Different boundary, different class of problem caught:

| Layer | Catches | This scaffold has it? |
|---|---|---|
| Agent hooks (pre-tool-use) | Agent about to exfiltrate a secret, run `curl \| bash`, edit outside scope | Yes — opt-in (`install.sh --claude`) |
| Linters (`ruff`, `eslint`) | Code quality once code is written | Yes |
| Git pre-commit | Debug leaks, file size, forbidden patterns at commit | Yes |
| CI mirror | All of the above, server-side, unskippable | Yes |

**The minimal version (now shipped).** `install.sh --claude` wires `PreToolUse` to `.githooks/lib/agent-precheck`, which scans the content of a Write/Edit/Bash call against `.forbidden-patterns/secrets.txt` — the same patterns the commit-time `check-secrets` uses. The same rule set runs in three places: agent → commit → CI. The bundled `.claude/settings.json` also denies the agent reading credential files (`.env`, `*.pem`, `~/.ssh/**`, `~/.aws/**`, …) outright.

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
