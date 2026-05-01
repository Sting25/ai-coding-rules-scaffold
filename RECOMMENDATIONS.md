# Recommendations

Things this scaffold deliberately doesn't do, but might be worth adopting in setups it isn't sized for. Each entry has explicit triggering conditions — adopt only if those apply to you.

## Maintenance

Entries are dated. If one has gone untouched for over a year, delete it (or move it to a GitHub issue with a `future-ideas` label). Active discussion belongs in issues, not here — a stale recommendation is worse than no recommendation.

---

## Agent-runtime hooks (Claude Code `PreToolUse`, Cursor `beforeShellExecution`, Gemini `BeforeTool`)

_Added 2026-04-23._

**Adopt if:** you have ≥3 concurrent agents, OR CI is rejecting more than ~1 violation/week that the agent could have caught at write-time, OR a single security incident from agent-issued shell commands has happened.

**What it is.** IDE-level hooks fire at the agent's action boundary — *before* the agent edits a file or runs a shell command. Git hooks (this scaffold) fire at the commit boundary, after the agent has already written the code. Different boundary, different class of problem caught:

| Layer | Catches | This scaffold has it? |
|---|---|---|
| Agent hooks (pre-tool-use) | Agent about to exfiltrate a secret, run `curl \| bash`, edit outside scope | No |
| Linters (`ruff`, `eslint`) | Code quality once code is written | Yes |
| Git pre-commit | Debug leaks, file size, forbidden patterns at commit | Yes |
| CI mirror | All of the above, server-side, unskippable | Yes |

**The minimal version.** Wire `PreToolUse` to invoke this scaffold's existing `lib/check-*` scripts on the file the agent is about to write. ~15 lines of `.claude/settings.json`, reuses code already in `.githooks/lib/`. The same script runs in three places: agent → commit → CI.

**The full version (overkill for most).** See [johnclick.ai/blog/hooks-based-enforcement-for-ai-agents](https://johnclick.ai/blog/hooks-based-enforcement-for-ai-agents/). Three-layer pattern (hooks + validators + guard YAMLs), four hook families (compliance / security / quality / orchestration), monitor → warn → enforce gradual rollout. Appropriate for production fleets of 10+ concurrent agents; overkill for small teams.

**Highest-ROI first hook if you only adopt one.** Shell-command security scan in `PreToolUse` — block `curl | bash`, credential patterns, destructive git commands before the agent runs them. Per the source article, this is the single highest-ROI agent hook.

**Why not in the scaffold.** Adopting the full framework dilutes the scaffold's "minimum-viable guardrails" identity. Adopting only the minimal version is plausible — tracked as a candidate for a future release, but unconfirmed.

---

## Spec-first workflow templates (`SPEC.md`)

_Added 2026-04-23._

**Adopt if:** team includes junior developers using AI as a senior engineer, OR features regularly land that don't match what was asked for, OR scope creep is the dominant failure mode in code review.

**What it is.** An opt-in `SPEC.md` template at the project root with sections for Problem / Non-goals / Constraints / Acceptance criteria / Open questions. Filled out *before* code starts. Anchors the agent to a defined scope and forces explicit non-goals — the section that catches AI scope creep most reliably.

**Why not in the scaffold.** Spec discipline is project-specific and team-specific. Imposing a template would push the scaffold from "rule enforcement" toward "process opinion," which is a different category of tool.

---

## Language-agnostic forbidden-patterns file

_Added 2026-04-22._

**Adopt if:** your repo has accidental git conflict markers landing in non-code files, OR you want to scan Markdown / YAML / JSON for AWS keys and credentials.

**What it would add.** `.forbidden-patterns/common.txt` alongside the existing `backend.txt` / `frontend.txt` / `secrets.txt` / `shell.txt`. Patterns that apply across every text file: git conflict markers (`^<{7}`), accidental AWS access keys outside `.env` files (`AKIA[0-9A-Z]{16}`), etc.

**Why not in the scaffold yet.** Could be added without scope creep — it's a fourth pattern file consumed by the existing `check-patterns` and `check-secrets` scripts. Held back pending demand or a specific incident that proves it's worth the maintenance.
