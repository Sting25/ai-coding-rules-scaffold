# Security & Code Audit — ai-coding-rules-scaffold

## Audit 2026-06-30 — full-tree re-audit (latest)

**Date:** 2026-06-30  ·  **Base:** HEAD of `main` (post-v0.8.0, commit `4ad17a9`)  ·  **Method:** 11-dimension multi-agent fan-out (68 agents) → per-finding adversarial verification (each finding reproduced in a throwaway git repo) → maintainer re-reproduction of the critical/high tier.

**Result:** 57 confirmed · 49 confirmed-as-stated · 8 partial · 0 refuted.

| Severity | Confirmed | Fixed on `fix/audit-2026-06-30` |
|---|---|---|
| critical | 1 | 1 |
| high | 9 | 3 |
| medium | 10 | 0 |
| low | 37 | 0 |

> ⚠️ **The historical sections below (2026-06-09/10, base `89ac255`, pre-PR #6) are STALE.** Several findings they mark `⬜ Open` have since been FIXED in shipped code, and one fix introduced a new critical bug. Trust *this* section over the per-finding `✅/⬜` markers further down:
> - *"sk- regex misses modern OpenAI/Anthropic keys"* → **FIXED**: `secrets.txt` now ships `sk-ant-`, `sk-proj-`, `sk-svcacct-`/`sk-admin-`.
> - *"Deleting the forbidden-patterns config disables the scan"* → **FIXED**: `pre-commit` now has the `DELETED_CONFIG` guard.
> - *"Combined-ERE ReDoS hang"* → **FIXED** with a `MAX_LINE_LENGTH` line cap — but that cap **fails OPEN** (new finding **A1** below).
> - *"scaffold-allow substring anywhere"* → **PARTIALLY fixed** (a comment leader is now required) but still bypassable (new finding **A3** below).

### 🔴 Critical

**A1 — Secret on a line longer than `MAX_LINE_LENGTH` is silently dropped (scanner fails OPEN)** — `githooks/lib/check-secrets.template:154-157` (same hole: `check-patterns.template:171-174`, `check-hygiene.template:106,163`, `agent-precheck.template:57-59`)
- **What:** the ReDoS guard drops any line longer than `MAX_LINE_LENGTH` (default 50000) via `awk 'length > n { next }'`, emits only a stderr warning, and never sets `FAILED` — exit stays `0`, in the local hook **and** `--ci` mode. A credential on a single >50k-char line (minified/no-newline blob) is never scanned.
- **Repro:** a 60000-char line + `AKIA…` → `--ci` prints "line(s) … dropped" and exits 0; the same key on a normal line exits 1. Verified end-to-end and via the awk pre-pass in isolation.
- **Fix:** the secret scanner must **fail closed** on a dropped line (report + `exit 1`), or scan the long line with a linear matcher (fixed-string prescreen / fixed-width windows). `agent-precheck` should fail closed on the Bash path.

### 🟠 High

- **A2 — `agent-precheck` block path fails OPEN via SIGPIPE** — `githooks/lib/agent-precheck.template:99-106`. `{ …; printf '%s\n' "$hit" | head -3; } >&2` then `exit 2`, under `set -euo pipefail`: with ≥4 matched lines, `head` closes the pipe, `printf`→SIGPIPE→141, `pipefail`+`set -e` abort **before `exit 2`**. Claude/Cursor treat only exit 2 as "block", so the matched Write/Bash is **allowed**. *Fix:* `printf … | head -3 || true`.
- **A3 — `scaffold-allow` can smuggle a real secret; documented "can't be smuggled" guarantee is false** — `check-secrets.template:167`, `check-patterns.template:188`, `check-hygiene.template:109,169`, `agent-precheck.template:96`. The exemption accepts a bare `--` anywhere on the line; secret charsets contain `-`, so `const k = "AKIA… -- scaffold-allow";` (marker inside the string, `--` not a comment in JS) suppresses the finding and exits 0. *Fix:* drop bare `--`, require the leader at start-of-line/after-whitespace, and correct the docs (inline suppression is inherently author-usable, like `# noqa`).
- **A4 — `check-filenames` matches credential filenames case-sensitively** — `check-filenames.template:39,48-57`. `*.pem`, `.env`, `id_rsa` are byte-compared, so `key.PEM`/`.ENV`/`ID_RSA` bypass on the case-insensitive filesystems (macOS/Windows) the project targets. Dual-layer bypass: `.ENV` with `INTERNAL_TOKEN=plainword` passes both scanners. *Fix:* lowercase via `tr` before matching (bash-3.2-safe).
- **A5 — Generic credential regex requires QUOTED values** — `secrets.txt.template:53`. `['"]…{16,}['"]` misses unquoted `.env`/YAML/shell/Dockerfile assignments (the dominant leak surface), JS backticks, and `=>` values. *Fix:* optional quotes + value terminator.
- **A6 — Underscore-prefixed credential names evade the same rule** — `secrets.txt.template:53`. `(^|[^A-Za-z_])` treats `_` as a word char, so `db_password`, `MY_API_KEY`, `DATABASE_PASSWORD` aren't matched even when quoted. *Fix:* change the boundary to `(^|[^A-Za-z])`.
- **A7 — `cp_safe` follows symlink destinations (arbitrary-path write; installed scanner left as a symlink)** — `install.sh:78-105`. `[ -e "$dst" ]` dereferences symlinks: a dangling symlink at a scaffold path makes `cp` write outside the repo and leaves the installed scanner as a symlink; a symlink→outside-file with `--force` overwrites that file. Gated on a planted symlink. *Fix:* `[ -e "$dst" ] || [ -L "$dst" ]`, `rm -f` before copy, `cp -P` for backups, guard the `cmp -s` no-op.
- **A8 — Several common cloud/SaaS credential formats have no prefix rule** — `secrets.txt.template:12-35`. SendGrid, Twilio (AC-SID + auth token), Mailgun, Square, Shopify, Azure Storage/AD, Mailchimp, Telegram bot tokens fall through to the (weakened) generic rule → unscanned. *Fix:* add prefix-anchored lines.
- **A9 — `scaffold-allow` exemption also smuggles past `check-hygiene`** — `check-hygiene.template:109,169` (hidden-Unicode / conflict markers). Same root cause as A3; *fix:* anchor the marker to a real trailing comment token.
- ~~**A10 — Test gap: `check-filenames` `*.pem` and SSH-key branches have zero tests**~~ **FIXED** — `tests/cases/04` #36c/#36d add lowercase `key.pem`/`id_rsa` plus every untested SSH alternative (`id_ed25519`/`id_ecdsa`/`id_dsa`) and the remaining `.env` allowlist entries (`.env.sample`/`.env.template`), each with the expected-substring guard. Teeth verified by mutation (breaking `*.pem` / dropping `id_ed25519` turns exactly the right cases red).

### 🟡 Medium

| Title | Location |
|---|---|
| Mid-script `cp`/`mkdir` failure aborts under `set -e` with no rollback/summary | `install.sh:103-104,145-274` |
| ~~Plain re-run keeps stale scaffold-owned scanners — security fixes never reach upgraders~~ **FIXED** — `cp_scaffold` refreshes scaffold-owned code on diff (see "installer upgrade story" below) | `install.sh` |
| Uninstall never removes `.githooks/lib/ci-changed-files` (install adds 8 libs, uninstall removes 7) | `uninstall.sh:133` |
| Generic credential keyword list omits `secret`, `client_secret`, `private_key`, `credential`, `pwd`, `auth` | `secrets.txt.template:53` |
| URL-embedded-credentials rule misses empty-username userinfo (a redis-style URL with an empty user) | `secrets.txt.template:48` |
| `agent-precheck` long-line filter empties content → exit 0, skipping a one-line Bash command scan | `agent-precheck.template:57-59` |
| Template-only action pins get neither Dependabot updates nor drift-guard coverage; rot silently | `gitleaks.yml.template:38` (+ `dependency-review`/`coverage`/opt-in `lint` jobs) |
| `dependency-review` defaults to `fail-on-severity: moderate`, allowing low-severity advisories | `dependency-review.yml.template:49` |
| `scaffold-allow` over-broad in hygiene (substring after any leader, in files with no comments) | `check-hygiene.template:109,169` |
| pre-commit stash push-failure and pop-conflict recovery paths are untested | `pre-commit.template:62-69,74-88` |

### ⚪ Low (themes; 37 findings)

- **Regex precision:** `check-secrets` `-i` false-positives on uppercase-only prefix tokens; leading whitespace before a pattern silently neuters it (`:102`); `backend.txt` `print()`/`os.path.join` unanchored (match `obj.print()`, comments); conflict-marker regex requires exactly 7 marker chars (8-run unmatched); hidden-Unicode scan skips any blob with a NUL in the first 8 KB (early NUL hides later Trojan-Source bytes); conflict/hidden-Unicode lines over `MAX_LINE_LENGTH` are dropped.
- **`.scaffold.toml` parser:** a backslash in a rule-id defeats the override (awk `-v` C-escape); `scaffold-audit` can over-report inert entries as active.
- **CI:** `check-hygiene` case-collision is diff-scoped in CI but the header claims whole-tree (`lint.yml.template:365`); `test.yml:66-68` pin-drift regex misses quoted `uses:`.
- **`DELETED_CONFIG` gap** (`pre-commit.template:38`, partial): blocks deleting `.forbidden-patterns/*.txt` but not the `check-*` scripts, `scaffold-config`, or the hook itself.
- **Uninstall** (partial): `--all` `rm -rf .forbidden-patterns` destroys user-authored pattern files (`uninstall.sh:159`); `awk`/`mv` failure in `clean_claude_md` aborts the rest of cleanup; `core.hooksPath --unset` can fail on a multivar value.
- **Test gaps:** ~~the `MAX_LINE_LENGTH` drop~~ **FIXED** (cases/04 #31/#31b — an over-cap line is reported and the commit rejected, while a short secret on a normal line is still caught); ~~invalid-pattern-dropped~~ **FIXED** via the shared validation (cases/02 #17 — an invalid ERE is dropped with a warning and valid patterns still scan; `check-secrets:120` is a literal twin of that branch); **combined-regex-invalid (`USE_PREFILTER=0`) — DEFERRED, not portably reproducible**: by construction the per-pattern pass drops any individually-invalid pattern *before* `COMBINED` is built and wraps each survivor as `(p)`, so a valid pattern can only break the combined ERE through an unbalanced paren a lenient grep (GNU) reads as a literal — which a strict grep (BSD) rejects alone and drops first; the valid-alone→invalid-combined window is empty across both CI greps, so the `USE_PREFILTER=0` fail-closed fallback is retained as defense-in-depth but isn't deterministically testable; ~~CI fail-closed-on-missing-config~~ **FIXED** (cases/04 #30 — `check-secrets --ci` with `secrets.txt` removed exits non-zero, "secret scanner is disabled"); ~~`ci-changed-files` fail-open branches~~ **FIXED** (cases/10 #6/#7 lock the `have()`-false fall-through for absent PR-base/push-before SHAs; #8 locks `changed_or_all`'s internal diff-error→whole-tree fallback, mutation-proven isolated). ~~the `.env.example` allowlist, and the `assert_rejects` that omit the expected-substring guard~~ **FIXED** — the `.env` allowlist entries are covered (A10 fix) and every `assert_rejects` across the whole suite (cases/01/02/04/05) now carries an expected-substring guard, so a test can no longer pass merely because the hook crashed for an unrelated reason.
- **Docs:** ~~`README.md` advertises `password=`/`token=` detection that only fires on quoted values (A5)~~ **FIXED** (the secret-scan row now says "quoted … assignments — unquoted/env-var forms are better caught by the gitleaks layer"); ~~"what lands" table omits `.github/dependabot.yml`~~ **FIXED** (present); ~~`--cursor` bullet omits the jq fail-open caveat~~ **FIXED** (says "needs `jq` and fails open"); ~~`forbidden-patterns/README.md` omits `.svelte`~~ **FIXED** (frontend.txt row now lists `*.svelte`, matching its `scaffold-extensions` header; the main README already documented it). Remaining: `SECURITY_AUDIT.md` (historical) stale "Open" statuses — mitigated by the "trust *this* section" banner atop the historical block; per-marker reconciliation deferred as high-churn/low-value.

### Fixed on this branch (`fix/audit-2026-06-30`)

Each landed with a red-then-green regression test; full suite 148/148 green.

- **A1 (critical)** — `check-secrets` now FAILS CLOSED on a line over `MAX_LINE_LENGTH` (reports it + fails) instead of dropping it with a warning and exit 0. The line is still dropped before the ERE, so the ReDoS guard is unchanged. (`2f79605`; tests cases/04 #31, #31b)
- **A2 (high)** — `agent-precheck` block path no longer takes SIGPIPE (`printf … | head -3 || true`), so it reliably reaches `exit 2` and actually blocks. (`98c6d41`; cases/07 #48g asserts the exit code is exactly 2)
- **A3 (high)** — `scaffold-allow` dropped bare `--` as a leader and now requires a start-of-line/whitespace boundary, across all five exemption sites (check-secrets, check-patterns, check-hygiene ×2, agent-precheck); over-claiming docs corrected. (`2a92e6e`; cases/04 #28b)
- **A4 (high)** — `check-filenames` folds name+path to lowercase before matching, so `.PEM`/`.ENV`/`ID_RSA` are blocked; the `.env.example` allowlist still holds. (`16ab43b`; cases/04 #36, #36b)

### Fixed in follow-ups (`fix/audit-secret-regex`)

Secret-regex coverage, each validated against a positive **and** negative FP corpus (SHA-256 / git-hash / UUID / lockfile-hash / unquoted-variable negatives) and locked with harness tests (`cases/01` #10a–g):

- **A6 (high)** — generic credential-rule boundary `[^A-Za-z_]` → `[^A-Za-z]`, so underscore-prefixed names (`db_password`, `DATABASE_PASSWORD`, `client_secret`) are caught.
- **A8 (high)** — added prefix/boundary-anchored rules: SendGrid, Shopify, Square, Mailgun, Telegram, Twilio (Account SID + API key SID). The hex-prefixed ones (`AC`/`SK`/`key-`) carry non-alphanumeric boundaries so they don't match a window inside a SHA.
- **medium** — keyword list broadened (`pwd`, bare `secret`, `private_key`, `credentials?`); URL-credentials rule now matches the empty-username userinfo form (e.g. a redis URL with an empty user).

**A5 (unquoted values) is deliberately NOT fixed.** Loosening the quote requirement false-positives on ordinary `api_key = some_variable` assignments. Per the project's standing decision (and the README), unquoted/env-var secrets are the gitleaks layer's job — the README's secret-scan row now says "quoted" explicitly and points there.

### Fixed in follow-ups (`fix/audit-installer`)

- **A7 (high)** — `cp_safe` no longer writes THROUGH a symlink at a scaffold path. `[ -e ]` is false for a dangling link and follows a live one, so a planted symlink used to make `cp` write the scanner to the link's target outside the repo (and leave the installed scanner as a symlink). Now: test `-L` too, never compare/no-op through a symlink, back up the link itself with `cp -P`, and `rm -f` the dst before writing a real regular file. (`install.sh`; tests `cases/09` live-force + dangling-no-force.)
- **chmod robustness (low)** — a new `mkx()` helper chmods only a real regular file, so a skipped (symlink) scaffold path can't abort the install via a chmod-through-a-broken-link under `set -e`. Replaces every `chmod +x` site.
- **uninstall gap (medium)** — the uninstall loop now includes `ci-changed-files` (install adds 8 libs; uninstall removed 7, leaving it orphaned). (`uninstall.sh:133`; test `cases/09`.)

### Fixed in follow-ups (installer upgrade story)

**The installer upgrade story is RESOLVED.** A plain re-run of `install.sh` is now the supported upgrade path, so security fixes reach an existing user just by re-running. `cp_safe` was one policy ("skip unless `--force`") applied to three kinds of file with conflicting needs; it's split into one write mechanism (`_cp_replace` + `_backup`, carrying the A7 symlink defenses) and three ownership policies:

- **`cp_scaffold` — scaffold-owned code** (`pre-commit`, all `.githooks/lib/*`, `commit-msg`, `lint.yml`, `coverage.yml`): **refreshes on diff with no `--force` needed**, so an upgrader receives the latest scanners/hooks/workflows by re-running. Identical → silent no-op; a symlink planted at a scaffold path is replaced with the real file (never written through); the prior bytes are recoverable from git + the scaffold, so a routine refresh writes no `.scaffold-bak` (only `--force` does). Announced as `updated: <path>`.
- **`cp_safe` — user-owned files** (`ruff.toml`, eslint/tsconfig/prettier/vitest, `.scaffold.toml`, `.github/dependabot.yml`, the rules docs): unchanged — skip unless `--force` (which backs up first). `CLAUDE.md`/`AGENTS.md` keep their dedicated merge handlers.
- **`cp_pattern` — `.forbidden-patterns/*.txt`** (the hard case: scaffold-shipped yet user-extended): a re-run only **notifies on drift** (`note (drift): …`) and keeps the user's file; `--force` backs up the user's rows to `.scaffold-bak` and writes the shipped version for manual merge-back.

Red-then-green tested in `tests/cases/09` (refresh-stale-scanner, refresh-stale-workflow, leave-user-config, notify-on-pattern-drift, `--force`-backs-up-drift, clean-no-op-when-current); full suite 164/164, shellcheck clean. The scope was deliberately limited to code/libs/workflows: the markdown rules docs (`coding-rules.md`/`operational-rules.md`) and `dependabot.yml` stay user-owned (`cp_safe`), since teams localize them.

**Still open** (priority order): the remaining test-coverage gaps (A10 et al.); and the remaining doc reconciliations.

### What's solid (verified, so fixes don't regress it)

Blob-scanning via `git show ":0:<path>"` (defeats symlink/NUL/post-stage edits); consistent `grep -a` text mode; up-front + combined-regex validation with fail-closed-to-per-pattern; GitHub-annotation escaping; the **non-overridable security boundary** (`check-secrets`/`check-filenames` genuinely never consult `.scaffold.toml` — verified by trace); `ci-changed-files` fail-open-to-whole-tree never emits a partial list; `lint.yml` hardening (SHA-pinned, `permissions: contents: read`, `persist-credentials: false`, env-routed expressions, `npm ci --ignore-scripts`); fail-closed test harness (`exit "$FAIL"`).

---

## Historical audit — 2026-06-09/10

**Date:** 2026-06-09  ·  **Base commit audited:** `89ac255` (pre–PR #6)  ·  **Method:** multi-agent fan-out audit (86 agents, 6 dimensions) → adversarial empirical verification (PoCs reproduced in throwaway git repos) → completeness critic.

**Result:** 73 candidates · **67 confirmed** (65 reproduced end-to-end) · 6 rejected by verification.

| Severity | Confirmed | Fixed in `fix/audit-blob-scan-and-revert-node20` |
|---|---|---|
| critical | 1 | 1 |
| high | 11 | 5 |
| medium | 13 | 2 (+1 partial) |
| low | 38 | 6 (+1 partial) |
| info | 4 | 1 |

> This scaffold is **installed into other repos**, so any scanner bypass propagates to every consumer. The findings below reflect that blast radius.

## Already addressed on this branch

- **PR #6 reverted** (`c08322c`) — it downgraded `actions/checkout`/`setup-python`/`setup-node` onto the force-deprecated **node20** runtime; node24 v6 SHAs restored.
- **Root Cause A — blob-based scanning** (`e8829e3`) — the four `lib/check-*` scanners now read the staged git blob (`git show ":0:<path>"`) with `-a/--text` and `-z` (NUL-delimited) enumeration, instead of the working-tree path over a newline-delimited list. One change retires the findings marked ✅ below:
  - CRITICAL: Single NUL byte in a source-extension file bypasses secret + pattern scans (whole-file binary detect…
  - HIGH: Dangling-symlink blob is a total secret bypass: [ -f "$f" ] is false, so the secret-carrying link bl…
  - HIGH: Live symlink: grep follows the link and scans the resolved target's content, never the committed blo…
  - HIGH: Filenames containing newline/tab control chars bypass ALL scanners (hook + CI) — core.quotepath=off…
  - HIGH: EXIT-trap `git stash pop` corrupts working tree and orphans stash on partial-staging (data loss)
  - HIGH: Newline / control-char filenames bypass BOTH hook and CI; quotepath=off fix only covers high-byte UT…
  - MEDIUM: CRLF-saved config silently disables any pattern whose line has no description column (fail-open secr…
  - MEDIUM: grep's NUL-byte binary auto-detection lets a secret line hide from check-secrets/check-patterns when…
  - LOW: check-filenames aborts on leading-dash filenames via unguarded basename (confusing failure, order-de…
  - LOW: `printf \| head -3 \| sed` aborts check-patterns/check-secrets via SIGPIPE under pipefail (exit 141)
  - LOW: Combined-ERE prefilter conflates grep error (exit 2) with no-match, skipping the file (fail-open con…
  - LOW: Scan reads working-tree/index via filesystem, not the git blob — divergence between scanned bytes an…
  - LOW: check-size silently passes oversized files whose name begins with `-` (MAX_LINES bypass)
  - LOW: stash pop conflict silently corrupts the working tree and strands unstaged work in a dangling stash
  - INFO: Lint step passes staged filenames to ruff/eslint without `--`, allowing option injection via filenam…
- Plus hardened stash-pop, combined-regex fail-closed, CRLF strip, `--` before lint filenames. See the commit body.

### Update 2026-06-09 — detection-efficacy pass (branch `fix/audit-detection-efficacy`)

High-specificity, low-false-positive pattern broadening (each validated against positive **and** negative corpora and locked in with harness fixtures #22–26):

- HIGH `sk- secret regex misses modern OpenAI/Anthropic keys` → added `sk-ant-` and `sk-proj-` patterns.
- HIGH `curl|bash guard misses the common form` → broadened to catch `curl -fsSL <url> | bash`, `wget -qO-`, `sudo`, multi-token, and no-space variants.
- MEDIUM `github_pat_ fine-grained PAT not covered` → added `github_pat_[A-Za-z0-9_]{22,}`.
- MEDIUM `rm -rf / guard misses /*, split flags, ~/$HOME` → broadened, while still **not** flagging scoped removals (`rm -rf /tmp/foo`, `node_modules`, `$BUILD_DIR`) — FP-guarded by fixture #25.
- LOW `AWS coverage limited to AKIA` → added `ASIA` temporary-session keys.
- **Regression fix:** PR #7's blob rewrite accidentally made `check-patterns` case-**insensitive** (`grep -aniE`); restored to case-sensitive (`grep -anE`) so identifiers like `Alert(`, `Console.log`, `Print(` are not false-matched (fixture #26).

Deliberately **not** done here (needs a design decision, not a regex tweak): the generic **unquoted / multi-line** hardcoded-credential gaps. Every loose regex either over-matches dotted identifiers (false positives, which erode trust) or still misses — this case is better served by layering a purpose-built secret scanner (gitleaks/trufflehog), the audit's standing recommendation. Tracked under Root Cause B below.

### Update 2026-06-09 — fail-closed config trust (branch `fix/audit-config-trust`, Root Cause C)

- HIGH `Deleting the forbidden-patterns config in the same commit disables the scan` → the hook now refuses a staged deletion of any `.forbidden-patterns/*.txt` (checked before the empty-staged-list exit, so a delete-only commit can't slip through); `--no-verify` remains the explicit escape for a genuine uninstall.
- HIGH (CI side) → `check-secrets --ci` now fails **closed** when `secrets.txt` is absent (it is always installed by the scaffold, so its absence server-side means the scanner was disabled).
- HIGH `scaffold-allow is a case-insensitive substring match anywhere on the line` → the marker is now honored **only after a comment leader** (`#`, `//`, `/*`, `<!--`, `--`), so it can't be smuggled inside a string literal to whitelist a real secret.
- MEDIUM `Config line missing a TAB is promoted to a whole-line pattern` → pattern lines without a TAB separator are now skipped with a warning.

Locked in with harness fixtures #27–30 (the #30 `--ci` test also begins closing the "harness never exercises the `--ci` path" finding). Still open from Root Cause C/D: escaping `::error` annotation fields (LOW), and a strict-token escape audit. 33/33 tests pass.

### Update 2026-06-09 — ReDoS guard + supply-chain pin (branch `fix/audit-redos-supplychain`)

- HIGH `Combined-ERE pre-filter blows up superlinearly on a long single line — hook and CI hang (ReDoS)` → both scanners now drop any line longer than `MAX_LINE_LENGTH` (default 50000, configurable) via a linear `awk` pass before the ERE ever sees it. Verified: an 800 KB single-line file now scans in ~0 s instead of hanging. A short secret on a normal line is still caught (fixture #31); over-long minified/generated lines are reported as skipped — point a dedicated scanner at those.
- LOW (supply-chain) `actionlint installed via curl|bash from a mutable git tag` → `test.yml` now pins the download script to the **commit SHA** of `rhysd/actionlint` tag v1.7.12 (`914e7df…`), so a moved tag or compromised release can't swap the installer.

34/34 tests pass; shellcheck clean. Remaining HIGH from the audit: rename-to-skip-listed-extension. Still open: fork-PR trusted-ref guardrails, Git-LFS blob scanning, `::error` annotation escaping, broader `--ci`/per-pattern fixtures, and the gitleaks-layer decision for generic unquoted secrets.

### Update 2026-06-10 — clean-fix batch (branch `fix/audit-batch-clean-fixes`)

- HIGH `Renaming a secret to a skip-listed extension smuggles it past the scan` → `check-secrets` extension allowlist **removed**; every tracked file's staged blob is scanned as text. A NUL "binary, skip" sniff was deliberately rejected (it reopens the NUL bypass); large blobs are still handled by the `MAX_LINE_LENGTH` line-drop. `check-size`'s skip is intentionally kept (quality nudge, not a security boundary). Fixtures #32–34.
- LOW `::error annotation fields echoed unescaped (annotation / file-target spoofing)` → all four `lib/check-*` scripts now percent-encode the `file=` property (`%`,CR,LF,`:`,`,`) and message body (`%`,CR,LF) per GitHub workflow-command rules. Fixture #35.
- MEDIUM `fork-PR-from-head guardrail` and `Git-LFS pointer scanning` → **documented** in `lint.yml.template` as inherent limitations with consumer hardening guidance (base-ref scan / branch protection; `lfs: true`), rather than shipping an untested workflow restructure.
- Docs: README `wc -l`, "all files", and file-scope-asymmetry claims corrected.

39/39 tests pass (the actionlint workflow-validation case now runs); shellcheck clean. Still open: broader uninstall/`--force`/`--all` fixtures, the `pull_request` hardening/runner notes, and the **gitleaks-layer decision** for generic unquoted secrets (needs a design call, not code).

**Status legend:** ✅ Fixed on this branch · 🟡 Partially addressed · ⬜ Open (tracked below).

## 🔴 Critical

### ✅ Fixed · `critical` — Single NUL byte in a source-extension file bypasses secret + pattern scans (whole-file binary detection), silently on GNU grep and on CI

- **Location:** `githooks/lib/check-secrets.template:79-92 (prefilter L79, attribution L83-84); identical defect in githooks/lib/check-patterns.template L81-87`  ·  *(reproduced: yes, confidence: high, dimension: completeness-probe)*
- **What:** check-secrets and check-patterns scan files with bare GNU/POSIX grep, passing neither -a nor --text nor --binary-files=text. grep's content-based binary detection trips on a single NUL byte anywhere in the file, treating the WHOLE file as binary. The scaffold's two-stage design then fails in two different ways depending on the grep implementation, and BOTH l…
- **Impact:** Defeats the core security promise (block secrets / forbidden patterns) for any file an attacker or careless committer can put a single NUL byte into while keeping a scannable source extension. Verified end-to-end against the real check-secr…
- **Recommendation:** Force text scanning so NUL no longer flips files to binary: add `-a` (GNU) / `--text` (or `--binary-files=text`) to BOTH the prefilter and the attribution grep calls in check-secrets.template and check-patterns.template. This makes GNU grep emit matching lines to stdout and makes ugrep scan the file…
- **Verifier note:** Finder's primary PoC (config.py) is bypassed at the check-secrets layer but is NOT a silent end-to-end bypass: ruff (in both the pre-commit hook and the CI python job) rejects a NUL-bearing .py as inv…

## 🟠 High

### ⬜ Open · `high` — sk- secret regex misses ALL modern OpenAI (sk-proj-) and Anthropic (sk-…) keys despite claiming to cover them

- **Location:** `forbidden-patterns/secrets.txt.template:17`  ·  *(reproduced: yes, confidence: high, dimension: detection-efficacy)*
- **What:** The pattern is `sk-[A-Za-z0-9]{48,}` with description 'OpenAI / Anthropic-style API key'. The character class `[A-Za-z0-9]` excludes `-` and `_`. Every current OpenAI and Anthropic key format contains those separators after the `sk-` prefix: OpenAI project keys are `sk-proj-...` and Anthropic keys are `sk-…...`. The segment immediately after `sk-` is only `p…
- **Impact:** A consumer who commits a real present-day OpenAI or Anthropic API key (the dominant case for the named providers) is NOT blocked by either the pre-commit hook or CI. The tool reports success and the secret merges. Because modern keys are us…
- **Recommendation:** Add explicit modern-key patterns: `sk-ant-[A-Za-z0-9_-]{20,}` and `sk-proj-[A-Za-z0-9_-]{20,}`, and broaden the legacy form to `sk-[A-Za-z0-9_-]{20,}` (or keep both). Test each against current real key shapes. Update the description/README claim to match what actually ships.
- **Verifier note:** Finding is accurate. Minor refinement to the impact statement about the hardcoded-credential fallback: the finder says it misses modern keys because it 'requires quotes.' True, but there is a second c…

### ⬜ Open · `high` — curl|bash shell guard misses the most common real form `curl -fsSL <url> | bash` (and sudo/multi-space/wget -qO-)

- **Location:** `forbidden-patterns/shell.txt.template:4`  ·  *(reproduced: yes, confidence: high, dimension: detection-efficacy)*
- **What:** Pattern `(^\|[^A-Za-z_])(curl\|wget)[[:space:]][^[:space:]]*[[:space:]]*\\|[[:space:]]*(bash\|sh\|zsh)([[:space:]]\|$)` allows exactly ONE whitespace-delimited token between the tool name and the pipe: `[[:space:]][^[:space:]]*[[:space:]]*\\|`. Real invocations almost always have flags AND a URL (two+ tokens). Verified on GNU grep 3.11: `curl https://x.sh \|…
- **Impact:** The README lists `curl \| bash` as one of three headline shell protections, but the single most common real-world spelling sails through both hook and CI. A consumer (or an AI agent writing a deploy script) commits `curl -fsSL https://get.e…
- **Recommendation:** Allow zero-or-more tokens before the pipe and an optional privilege-escalation word after it, e.g. `(^\|[^A-Za-z_])(curl\|wget)([[:space:]]+[^\|]*)?\\|[[:space:]]*(sudo[[:space:]]+)?(bash\|sh\|zsh)`. Add positive test fixtures for `-fsSL`, `-qO-`, `sudo bash`, and multi-space variants in tests/run.s…
- **Verifier note:** Finding is accurate as written; no correction to scope, mechanism, or severity. Minor environmental note: on this host the default `grep` is ugrep 7.5.0, not GNU grep — but I confirmed the bypass on B…

### ⬜ Open · `high` — Deleting the forbidden-patterns config in the SAME commit disables the scan — config removal is not itself flagged

- **Location:** `githooks/lib/check-secrets.template:19-20`  ·  *(reproduced: yes, confidence: high, dimension: scanner-bypass)*
- **What:** check-secrets does `[ -f "$CONFIG" ] \|\| exit 0` and check-patterns does `[ -f "$config" ] \|\| return 0`. Because the hook stashes unstaged changes so the working tree matches the index, a single commit that `git rm`s `.forbidden-patterns/secrets.txt` makes the config absent at scan time, so check-secrets exits 0 (no-op) for that same commit. check-filenam…
- **Impact:** A malicious or compromised contributor can land a secret AND silently neuter the secret/pattern scanner for the whole repo in one atomic commit that passes the hook and CI. Verified: `git rm .forbidden-patterns/secrets.txt` + add `AKIA...`…
- **Recommendation:** Treat a missing/removed config as fail-closed in CI (the guardrails job should error if `.forbidden-patterns/secrets.txt` is absent), and have the hook/CI refuse a commit that deletes or empties a `.forbidden-patterns/*.txt` file (or warn loudly). At minimum, CI should assert the expected config fil…
- **Verifier note:** The finding is accurate. One clarification/strengthening: the finder attributes the bypass to the stash making the working tree match the index, which is correct, but there is an additional independen…

### ⬜ Open · `high` — scaffold-allow opt-out is a case-insensitive substring match anywhere on the line — trivially whitelists real secrets and over-matches

- **Location:** `githooks/lib/check-secrets.template:83`  ·  *(reproduced: yes, confidence: high, dimension: scanner-bypass)*
- **What:** Exemption is implemented as `grep -niE -- "$pat" file \| grep -iv 'scaffold-allow'` (and identically in check-patterns line 86). Any line containing the substring `scaffold-allow` ANYWHERE — including inside a string literal, a URL, a variable name, or arbitrary prose — is dropped from the violation set for BOTH the pattern and secret checks. It is not a tra…
- **Impact:** An attacker who can get any text containing 'scaffold-allow' onto the same physical line as a secret exfiltrates it past the scanner. Even benign-looking lines like `note = "see scaffold-allow ticket"; password = "<a real 16+ char secret>"` smu…
- **Recommendation:** Require the marker as a strict end-of-line comment token (e.g. match `(#\|//)\s*scaffold-allow\b` at line end only), and consider NOT honoring scaffold-allow for the secrets check at all (or require an explicit secret-specific token), so a code-style opt-out cannot whitelist credentials. Document th…
- **Verifier note:** Finder's framing is essentially accurate. One nuance: the claim that 'even benign-looking lines' smuggle credentials slightly overstates accidental risk — 'scaffold-allow' is a project-specific litera…

### ✅ Fixed · `high` — Renaming a secret/oversized payload to a skip-listed extension or path smuggles it past both checks

> **Fixed (secret scan):** `check-secrets` no longer skips by extension — every
> tracked file's staged blob is scanned as text. A NUL-byte "binary, skip"
> sniff was deliberately rejected (it would reopen the NUL bypass closed by the
> dangling-symlink/NUL findings); large minified/binary blobs are instead
> dropped by the existing `MAX_LINE_LENGTH` cap. Harness fixtures #32–34 cover
> `secret.png`, `secret in package-lock.json`, and NUL+binary-extension.
> **Note (size scan):** `check-size`'s extension skip is intentionally retained
> — it's a code-modularity nudge, not a security boundary, and content-scanning
> data files (`.csv`/`.sql`/`.json`) for line count would false-positive on
> legitimate large data. Renaming code to dodge the line cap has no security
> impact.

- **Location:** `githooks/lib/check-secrets.template:25-34`  ·  *(reproduced: yes, confidence: high, dimension: scanner-bypass)*
- **What:** check-secrets skips a large extension list (*.svg,*.png,*.jpg,*.lock,*.zip,... and package-lock.json/pnpm-lock.yaml/go.sum) and the entire `.forbidden-patterns/*` directory. check-size (check-size.template line 27-30) skips *.md,*.json,*.toml,*.yaml,*.yml,*.lock,*.txt,*.csv,*.sql and image types. These are name-based, not content-based, so renaming a text pa…
- **Impact:** A plaintext AWS key in `secret.png` or `package-lock.json`, or a 600-line code file renamed to data.sql/big.txt, passes silently in both hook and CI. Storing real credentials in any file under `.forbidden-patterns/` is wholly unscanned. Ver…
- **Recommendation:** For check-secrets, gate the skip on actual binary content (e.g. NUL-byte sniff via `grep -qI`) rather than extension, so a text file with a binary extension is still scanned. Do not blanket-skip `.txt`/`.csv`/`.sql` for size, or at least scan them for secrets. Reconsider skipping the whole `.forbidd…
- **Verifier note:** The finder's "passes silently in both hook and CI" is accurate and verified (I confirmed CI --ci mode also returns exit 0). One nuance: the pure rename attack (e.g. secret.png) requires deliberate int…

### ✅ Fixed · `high` — Dangling-symlink blob is a total secret bypass: [ -f "$f" ] is false, so the secret-carrying link blob is never scanned (hook AND CI)

- **Location:** `githooks/lib/check-secrets.template:36, 78-79`  ·  *(reproduced: yes, confidence: high, dimension: completeness-probe)*
- **What:** A symlink's committed blob content is its target path STRING. When the target does not exist (a dangling symlink), git still stages and commits the link as an ordinary Added (A) blob — it is NOT a type-change (T), so it survives the pre-commit `--diff-filter=ACMR` filter (githooks/pre-commit.template:28) and appears in CI's `git ls-files` (lint.yml.template:…
- **Impact:** Any contributor (or compromised dependency / malicious PR) can commit an AWS key, GitHub PAT, Slack token, OpenAI key, or URL-embedded credential to any consumer repo by encoding it as a dangling-symlink target string. The scanner the tool…
- **Recommendation:** Scan the COMMITTED BLOB, not the filesystem-resolved file. In the hook, derive content via `git show :"$f"` (index) and in CI via `git show "HEAD:$f"` / `git cat-file -p`, piping that to grep instead of passing the path. At minimum, explicitly detect symlinks (`[ -L "$f" ]` or `git ls-files -s`/`git…
- **Verifier note:** Finding is accurate. One scope refinement to the "any secret" claim: the bypass only works for secrets that can be expressed as a single-line, NUL-free, valid POSIX path string (a symlink target). The…

### ✅ Fixed · `high` — Live symlink: grep follows the link and scans the resolved target's content, never the committed blob — a secret-bearing target string ships undetected even when [ -f ] passes

- **Location:** `githooks/lib/check-secrets.template:79, 83`  ·  *(reproduced: yes, confidence: high, dimension: completeness-probe)*
- **What:** Even when a symlink IS live (`[ -f "$f" ]` true because it resolves to a real regular file), the scanner still never inspects the blob. `grep -niE -- "$COMBINED" "$file"` (check-secrets:79) and the per-pattern `grep` at :83 follow the symlink and read the RESOLVED TARGET's bytes, while the committed blob is the target PATH STRING. The two are completely disj…
- **Impact:** A second, complementary bypass for the same root cause: secrets/forbidden content can be smuggled in a symlink's target-path string even when the link resolves (so it passes `[ -f ]`), because the scanner reads the wrong bytes. Combined wit…
- **Recommendation:** Same fix as the dangling-link finding: scan blob bytes (`git show :"$f"` / `git cat-file -p`) rather than the filesystem path. If symlinks are genuinely needed in consumer repos, scan the link's target string as the content of interest. Never let grep follow a committed link to filesystem content th…
- **Verifier note:** Mechanism and reproduction are accurate as reported. Correction only to exploitation framing/blast radius: the finder's impact line implies near-universal evasion, but the LIVE-symlink secret bypass r…

### ⬜ Open · `high` — Combined-ERE pre-filter exhibits superlinear (≈O(n²)) blowup on long single lines — pre-commit hook and CI hang indefinitely (ReDoS)

- **Location:** `githooks/lib/check-secrets.template:68-79`  ·  *(reproduced: yes, confidence: high, dimension: completeness-probe)*
- **What:** check-secrets builds COMBINED='(p1)\|(p2)\|...' from all secret patterns and runs `grep -niE -- "$COMBINED" "$file"` as a per-file pre-filter (line 79). GNU grep 3.11 (the grep a bash script invokes on consumer/CI Linux machines — verified `bash script.sh` resolves `grep` to /usr/bin/grep, not the host's ugrep shim) does NOT blow up on any single pattern, bu…
- **Impact:** A single committed/staged file containing one long line of mixed alphanumeric content (a minified JS/CSS vendor bundle, a webpack chunk, a base64 data-URI, a source-map) hangs the pre-commit hook forever. The user must Ctrl-C; and the CI gu…
- **Recommendation:** Do not rely on a single combined ERE as the speed pre-filter. (1) Cap line length / file size before scanning (e.g. skip or hard-fail files with any line > N KB, or feed grep a length guard); (2) prefer `grep -F`-able fixed prefixes where possible and/or run patterns individually (the per-pattern gr…
- **Verifier note:** Finder's core claim is correct and the verbatim PoC reproduces (exit 124, hung). Refinements: (1) The finder framed the trigger as needing a crafted 48-char sk- key; it is actually far more reachable…

### ✅ Fixed · `high` — Filenames containing newline/tab control chars bypass ALL scanners (hook + CI) — core.quotepath=off does not stop control-char C-quoting

- **Location:** `githooks/pre-commit.template:24-28, 64-67`  ·  *(reproduced: yes, confidence: high, dimension: scanner-bypass)*
- **What:** STAGED is computed with `git -c core.quotepath=off diff --cached --name-only` (newline-separated, no -z). The in-code comment (lines 24-27) claims core.quotepath=off prevents the C-quoting bypass, but quotepath=off only disables OCTAL escaping of non-ASCII/high-bit bytes — it does NOT disable C-quoting of control characters. A path containing a newline or ta…
- **Impact:** An attacker (or a careless AI agent) can commit a file named `a<newline>b.py` (or with a tab) containing an AWS key / private key / oversized blob and it passes both the pre-commit hook (exit 0) and the CI guardrails job (exit 0). Defeats t…
- **Recommendation:** Use NUL-delimited iteration end-to-end: `git -c core.quotepath=off diff --cached -z --name-only --diff-filter=ACMR` (and `ls-files -z`) piped to `while IFS= read -r -d '' f`. NUL-mode does not C-quote any path. Alternatively, after reading, detect/reject paths that begin with `"` and end with `"` (t…
- **Verifier note:** Finding's mechanism, reachability, and dual-surface (hook + CI) reproduction are all accurate; the in-code comment's premise that quotepath=off prevents the bypass is indeed wrong (it only stops octal…

### ✅ Fixed · `high` — EXIT-trap `git stash pop` corrupts working tree and orphans stash on partial-staging (data loss)

- **Location:** `githooks/pre-commit.template:44-61`  ·  *(reproduced: yes, confidence: high, dimension: shell-robustness)*
- **What:** When a file is partially staged — staged changes AND further unstaged edits to overlapping lines (git's "MM" state, the normal `git add -p` / edit-after-add workflow) — the hook runs `git stash push --keep-index` (line 44), then on EXIT the trap runs `git stash pop --quiet 2>/dev/null \|\| true` (line 58). The `--keep-index` stash records both the index and…
- **Impact:** A developer who stages part of a file and keeps editing it (an everyday git workflow) silently gets conflict markers injected into their working file, the index left in an unmerged state, and a dangling stash they were never told about — wh…
- **Recommendation:** Detect a failed/conflicted pop and surface it loudly instead of swallowing it: capture `git stash pop` output and exit code; on non-zero, print a clear error pointing the user at `git stash list` / how to recover, and FAIL the hook (exit non-zero) so the commit does not silently proceed over a corru…
- **Verifier note:** The core mechanism is exactly right and reproduces cleanly, but one factual claim is overstated and must be corrected. The finding says the hook "exits 0 — the commit proceeds" and "the commit succeed…

### ✅ Fixed · `high` — Newline / control-char filenames bypass BOTH hook and CI; quotepath=off fix only covers high-byte UTF-8

- **Location:** `githooks/pre-commit.template:24-28,64-67`  ·  *(reproduced: yes, confidence: high, dimension: correctness-quality)*
- **What:** The hook (line 28) and CI (lint.yml.template line 71) both fix the C-quoting bypass by passing `-c core.quotepath=off`, and the comment (lines 24-27) plus CHANGELOG v0.4.0 'Security' entry frame this as closing the filename-based scan bypass. But `core.quotepath=off` only stops C-quoting of bytes >0x7F (non-ASCII); git STILL C-quotes filenames containing con…
- **Impact:** A file whose name contains a newline (or tab/quote) and contains a secret, debug statement, blocked content, or is oversized passes every scanner in both the local hook and server-side CI. This is a complete bypass of the tool's core promis…
- **Recommendation:** Use NUL-delimited enumeration end-to-end: `git -c core.quotepath=off diff --cached -z --name-only --diff-filter=ACMR` (and `ls-files -z` in CI) piped to lib checks reading with `while IFS= read -r -d '' f`. Add harness fixtures for newline/tab/quote filenames so the bypass class is actually tested.
- **Verifier note:** Finding is accurate as written. Minor precision notes: (a) the trigger is any control character or the double-quote/backslash characters in a filename (not strictly newline) — git C-quotes the set ind…

## 🟡 Medium

### 🟡 Documented · `medium` — Distributed guardrails job runs check scripts and pattern lists from PR head — a fork PR can neuter the server-side guardrail

> **Documented, not structurally changed.** This is inherent to a
> `pull_request` workflow running detectors from PR head (the verifier note
> below confirms it grants no new code-exec beyond the existing python/frontend
> jobs). The `guardrails` job in `lint.yml.template` now states this in-file:
> it is defense in depth, not a trust boundary against a hostile fork — pair it
> with branch protection / required review, and for untrusted forks gate merges
> on a scan run from the base ref. A full base-ref-checkout restructure is left
> as a documented consumer option rather than shipped untested.

- **Location:** `.github/workflows/lint.yml.template:60-77`  ·  *(reproduced: yes, confidence: high, dimension: supply-chain-ci)*
- **What:** The `guardrails` job is the server-side mirror of the pre-commit hook. It does `chmod +x .githooks/lib/check-*` and runs `.githooks/lib/check-{size,patterns,filenames,secrets}` (lines 68-76) — but these scripts, and the `.forbidden-patterns/*.txt` config files they read, are taken from the PR HEAD (the checked-out merge ref). On a `pull_request` event the sa…
- **Impact:** The tool's core promise — 'block secrets, forbidden patterns, oversized files, bad filenames server-side via CI' — is defeated for exactly the PR that is trying to sneak content past it. CI shows a green guardrails check, lowering reviewer…
- **Recommendation:** Run the check scripts and pattern configs from a TRUSTED ref (e.g., checkout the base branch's .githooks/.forbidden-patterns, or pin/vendor them), then scan the PR's file contents with the trusted scanner. Alternatively gate guardrails behind a separate workflow that fetches the scanner from the bas…
- **Verifier note:** This is not a code bug but an inherent property of `pull_request` workflows running detectors from PR head; it grants no new code-exec beyond the existing python/frontend jobs (which already run ruff/…

### 🟡 Documented · `medium` — CI guardrails scan reads the working tree by path, so a Git-LFS (or clean/smudge-filter) consumer repo can ship a secret in the committed blob while CI scans only the LFS pointer text — server-side-only bypass of the unskippable backstop

> **Documented, not structurally changed.** The scanners read the committed
> blob (`git show :0:<path>`), which for an LFS-tracked file is the pointer,
> not the smudged content — so LFS-stored text isn't meaningfully scanned. A
> generic fix means trusting the smudge filter (fetch LFS, scan the working
> tree) which is fragile and LFS-config-specific. The `guardrails` job now
> documents the limitation and points consumers at `lfs: true` + working-tree
> scanning if they keep scannable text in LFS.

- **Location:** `.github/workflows/lint.yml.template:65-77`  ·  *(reproduced: yes, confidence: high, dimension: completeness-probe)*
- **What:** Both check-secrets and check-patterns scan the WORKING TREE by path: they `[ -f "$f" ]`-test a path from `git ls-files` and then `grep -nE -- "$pat" "$file"`. They never read the committed blob (`git show :file` / `git cat-file -p HEAD:file` / `git grep --cached`). Git's content-filtering layer (gitattributes `filter=` clean/smudge, of which Git-LFS is the c…
- **Impact:** A consumer repo that uses Git-LFS (extremely common for any repo with binary assets, models, datasets, fixtures) gets a server-side scanner that is blind to the real content of every LFS-tracked file. An attacker (or a careless committer) c…
- **Recommendation:** Scan committed blobs, not the working tree, in the CI guardrails job. Options: (1) set `with: lfs: true` on actions/checkout in lint.yml.template AND `--no-text`/`-a` so smudged content is fetched — but this still trusts the smudge and is fragile; better (2) make the lib/check-* scripts read content…
- **Verifier note:** Direction of the LFS divergence in the finder's description/PoC is backwards: in real Git-LFS the committed blob is the pointer and the real secret lives in the out-of-band LFS object store (not "comm…

### ⬜ Open · `medium` — Hardcoded-credential regex misses unquoted assignments, env exports, YAML, and common credential keywords

- **Location:** `forbidden-patterns/secrets.txt.template:30`  ·  *(reproduced: yes, confidence: high, dimension: detection-efficacy)*
- **What:** Pattern requires surrounding quotes `['"]` and one of only six keywords `password\|passwd\|token\|api[-_]?key\|secret[-_]?key\|access[-_]?token`. Verified MISS on GNU grep 3.11 for: `password: hunter2supersecretvalue` (YAML, no quotes), `export TOKEN=abcdefghij1234567890longvalue` (unquoted), `PASSWORD=abcdefghij1234567890longvalue` (unquoted), `aws_secret_a…
- **Impact:** Credentials in .env files, docker-compose env, GitHub Actions YAML, and shell exports are not detected. Combined with the sk- gap above (modern keys are unquoted env vars), the credential-detection story has a large hole exactly where real…
- **Recommendation:** Make the surrounding quotes optional and add a word-boundary terminator for the value (e.g. value class `[A-Za-z0-9_/+=.-]{16,}` with optional quotes), and broaden keywords to include `secret`, `client_secret`, `private_key`, `auth`, `aws_secret_access_key`, `apikey`. Be mindful that dropping the qu…
- **Verifier note:** Finder is accurate. One clarification/important caveat for the consumer of this finding: whether a given leaked secret slips through depends on the secret VALUE as well as the keyword/quoting. The hoo…

### ⬜ Open · `medium` — GitHub fine-grained PAT (github_pat_...) prefix not covered by gh[pousr]_ pattern

- **Location:** `forbidden-patterns/secrets.txt.template:15`  ·  *(reproduced: yes, confidence: high, dimension: detection-efficacy)*
- **What:** Pattern `gh[pousr]_[A-Za-z0-9]{36,}` matches classic tokens (ghp_, gho_, ghu_, ghs_, ghr_) — verified `ghp_<40>` FIRES. But GitHub fine-grained personal access tokens use the prefix `github_pat_` followed by base62 plus underscores, which `gh[pousr]_` cannot match (`github_pat_...` MISS verified). Fine-grained PATs are now GitHub's recommended token type, so…
- **Impact:** A committed fine-grained GitHub PAT is not detected by hook or CI, despite README listing 'GitHub tokens' as covered.
- **Recommendation:** Add a dedicated pattern `github_pat_[A-Za-z0-9_]{22,}` (the prefix plus the two underscore-separated segments). Keep the existing classic-token pattern.
- **Verifier note:** Finding is accurate. Minor refinement: the finder's PoC token string is a shortened illustrative form, but the regex verdict (no match, exit 1) holds for full realistic fine-grained PAT shapes too. Th…

### ⬜ Open · `medium` — BEGIN-PRIVATE-KEY pattern only matches the header line; never validates key body, and is defeated by splitting/concatenating the header

- **Location:** `forbidden-patterns/secrets.txt.template:20`  ·  *(reproduced: yes, confidence: high, dimension: completeness-probe)*
- **What:** `-----BEGIN [A-Z ]*PRIVATE KEY-----` matches per-line (grep -nE). It fires ONLY on the literal header line and never inspects the actual key material on subsequent lines. Because the engine is wholly per-line with no multi-line/continuation awareness, the most sensitive credential type is detected by its least-secret token (a public, well-known marker string…
- **Impact:** Any private key whose PEM header is split across a string concatenation, written with a line break, or emitted programmatically passes the scanner with the full key body intact in the repo. A consumer relying on the scaffold to 'block secre…
- **Recommendation:** Add a body-shaped pattern in addition to the header (e.g. detect long contiguous base64 runs `[A-Za-z0-9+/]{60,}={0,2}` characteristic of key material, with allowlisting), and/or run a multi-line scan mode (grep -z / pcregrep -M) so the header+body block is matched as a unit. Document that line-spli…
- **Verifier note:** Finder is accurate on mechanism and PoC. One scope correction: the claim that a key 'written with a line break' bypasses is true only when the line break splits the header token itself; an ordinary in…

### ⬜ Open · `medium` — Hardcoded-credential regex defeated by splitting the value across string-concatenation / continuation lines

- **Location:** `forbidden-patterns/secrets.txt.template:30`  ·  *(reproduced: yes, confidence: high, dimension: completeness-probe)*
- **What:** The hardcoded-cred pattern requires keyword + `[:=]` + a single quoted run of `[A-Za-z0-9_/+=-]{16,}` on ONE line. Because matching is per-line, breaking the value into sub-16-char quoted runs concatenated across lines defeats the 16-char minimum. Verified: `password = "Sup3rSecr3t" + "PasswordValue99"` -> exit 0 (neither quoted run is >=16 chars), and `secr…
- **Impact:** The credential-assignment heuristic — the only pattern meant to catch generic secrets without a known prefix — is bypassed by ordinary multi-line string formatting that linters/formatters often produce anyway. Secrets land undetected in con…
- **Recommendation:** Accept that a pure per-line regex cannot enforce this; add a multi-line pass and/or relax the 16-char-contiguous requirement to a total-length heuristic after logical-line joining. Document the limitation.
- **Verifier note:** No misdiagnosis. The finder's mechanism, PoC, and both bypass variants reproduce exactly. One scoping nuance worth recording: this affects only the generic credential-assignment heuristic (the lone un…

### ⬜ Open · `medium` — rm -rf / guard misses `rm -rf /*`, split flags `rm -r -f /`, long-form flags, and `~`/$HOME

- **Location:** `forbidden-patterns/shell.txt.template:5`  ·  *(reproduced: yes, confidence: high, dimension: detection-efficacy)*
- **What:** Pattern `(^\|[^A-Za-z_])rm[[:space:]]+-[rfRF]+[[:space:]]+/[[:space:]]*([;&]\|$)` requires the slash to be immediately followed by end/`;`/`&`. Verified on GNU grep 3.11: `rm -rf /` FIRES, but `rm -rf /*` MISSES (the `*` after `/` defeats the trailing anchor) — and `rm -rf /*` is the more destructive, equally common footgun. Also MISSES: `rm -r -f /` (flags…
- **Impact:** The headline `rm -rf /` protection is bypassed by trivially common variants, including the catastrophic `rm -rf /*`. An agent-generated cleanup script using any of these forms commits clean. False sense of safety.
- **Recommendation:** Relax the trailing context to also accept `/*`, whitespace then more args, and quotes; recognize split/long flags and root-equivalent targets (`/`, `/*`, `~`, `$HOME`, `"$HOME"`). E.g. allow `rm[[:space:]]+(-[a-zA-Z]+[[:space:]]+)+(/[*]?\|~\|"?\$HOME"?)([[:space:]]\|/\|$)`. Add fixtures for each var…
- **Verifier note:** Finder's claims (variants missed, mechanism, PoC) are all accurate and fully reproduced on both the pre-commit and CI enforcement paths. Only adjustment: severity high -> medium. This is a detection-e…

### 🟡 Partial · `medium` — Combined-ERE pre-filter is fail-open and its concatenation is never validated; literal close-paren and grep-implementation differences can alter semantics

- **Location:** `githooks/lib/check-patterns.template:63-81`  ·  *(reproduced: yes, confidence: high, dimension: scanner-bypass)*
- **What:** Patterns are validated INDIVIDUALLY via `printf '' \| grep -E` (empty input, GNU-grep semantics), then concatenated as `(p1)\|(p2)\|...` and used as a fast pre-filter: `grep -nE -- "$combined" "$file" >/dev/null 2>&1 \|\| continue`. The combined form is never validated. If the combined regex ERRORS at runtime (grep exit 2), `\|\| continue` SKIPS the file (fa…
- **Impact:** A single malformed-but-individually-accepted custom pattern can disable the pre-filter for whole files in the consumer's environment, dropping them from the scan (fail-open). Even without an attacker, cross-grep portability can silently tur…
- **Recommendation:** Validate the COMBINED regex after building it (printf '' \| grep -E -- "$combined") and fail CLOSED if it errors (scan every matching file per-pattern, or abort the commit), never `\|\| continue` past a grep error. Distinguish grep exit 1 (no match) from exit 2 (error): only treat exit 1 as 'skip fi…
- **Verifier note:** The fail-open `\|\| continue` mechanism and the consequence (silent scanner bypass dropping a whole file) are REAL and reproduced. But the finder overstated reachability on the dominant GNU-grep envir…

### ✅ Fixed · `medium` — CRLF-saved config silently disables any pattern whose line has no description column (fail-open secret bypass)

- **Location:** `githooks/lib/check-secrets.template:43-48`  ·  *(reproduced: yes, confidence: high, dimension: completeness-probe)*
- **What:** The config parse loop `while IFS=$'\t' read -r pattern description; do` does not strip a trailing carriage return. On a config file saved with CRLF line endings (Windows/many editors, or a checkout under git `core.autocrlf=true`), each physical line ends in `\r`. `read` splits on TAB: if the line HAS a description column the `\r` lands harmlessly on `descrip…
- **Impact:** A consumer who edits `.forbidden-patterns/secrets.txt` (or backend/frontend/shell.txt) on Windows or in an editor that writes CRLF, and adds a custom pattern without a description, will have that pattern silently neutralized in BOTH the pre…
- **Recommendation:** Strip a trailing CR during parsing, e.g. `pattern=${pattern%$'\r'}` and `description=${description%$'\r'}` right after `read`, or normalize the whole config with `tr -d '\r'` before the loop. Additionally ship a `.gitattributes` entry (`*.txt text eol=lf` for the forbidden-patterns dir) and document…
- **Verifier note:** Finder's host claim is wrong: on the audit host /usr/bin/grep == /bin/grep (same inode 1049233, GNU grep 3.11); ugrep is only an interactive-shell alias, so non-interactive git hooks already use GNU g…

### ⬜ Open · `medium` — Config line missing a TAB is silently promoted to a whole-line pattern with an empty description

- **Location:** `githooks/lib/check-secrets.template:43-47`  ·  *(reproduced: yes, confidence: high, dimension: completeness-probe)*
- **What:** `read -r pattern description` with `IFS=$'\t'` puts the entire line into `pattern` when there is no TAB. A maintainer note that forgot the leading `#`, or any malformed line (e.g. `remember to also add the GCP pattern here`), is not a comment (the `case "$pattern" in \#*) continue ;; esac` guard only skips lines literally starting with `#`) and is not empty,…
- **Impact:** Two consequences: (1) Correctness/false-positive — any committed file containing that text is flagged as a violation and the commit/CI is blocked for a non-secret. (2) In CI mode the violation is reported as `::error file=$file::$desc` with…
- **Recommendation:** Require a real TAB on each pattern line: skip (with a stderr warning) any non-comment, non-blank line that contains no TAB, or treat the absence of a description as an error. At minimum, refuse to keep a pattern whose description is empty when not intended, and warn loudly so malformed lines are vis…
- **Verifier note:** Two corrections. (1) The finder's concrete PoC file `readme_note.py` is misleading: a prose line in a .py file is rejected by ruff (invalid Python syntax) before the check-secrets empty-description be…

### ✅ Fixed · `medium` — grep's NUL-byte binary auto-detection lets a secret line hide from check-secrets/check-patterns when the file contains any NUL byte (no -a/--text flag)

- **Location:** `githooks/lib/check-secrets.template:79,83`  ·  *(reproduced: yes, confidence: high, dimension: completeness-probe)*
- **What:** check-secrets (and check-patterns) run `grep -niE -- "$COMBINED" "$file"` and `grep -niE -- "$pat" "$file"` without `-a`/`--text`. grep (both GNU grep on ubuntu-latest CI runners and ugrep on this host) auto-detects a file as binary if it contains a NUL byte and then reports no matches (exit 1) instead of scanning line content. The extension filter only excl…
- **Impact:** An attacker can append (or embed) a single NUL byte to an otherwise-text file containing a hardcoded secret or forbidden pattern; both the local hook and the CI guardrails job will skip the file as 'binary' and pass green, even though the s…
- **Recommendation:** Pass `-a` (or `--text` / for ugrep `--text`) to every grep invocation in check-secrets.template and check-patterns.template so files are scanned as text and NUL bytes do not abort the scan: `grep -aniE -- "$pat" "$file"`. Add a tests/run.sh case committing a NUL-containing file with a secret on a te…
- **Verifier note:** Finder's mechanism and severity are accurate. Two refinements: (1) For linted source extensions (.py/.ts/.js/.tsx/.jsx/.sh), the pre-commit hook and CI also run ruff/eslint separately, which can incid…

### ⬜ Open · `medium` — sk-/AWS/URL-cred secrets split across physical lines (backslash continuation or implicit string concatenation) evade detection

- **Location:** `githooks/lib/check-secrets.template:79-83`  ·  *(reproduced: yes, confidence: high, dimension: completeness-probe)*
- **What:** The whole engine matches per physical line (`grep -nE`), with no continuation/concatenation awareness. Verified bypasses: (a) `API_KEY = (\n  "sk-"\n  "<48 chars>"\n)` — prefix on one line, body on next — exit 0, while the single-line form is flagged. (b) `DB_URL = (\n  "postgres://admin:"\n  "<pass>@host/prod"\n)` — the URL-cred regex needs scheme+user+`:`+…
- **Impact:** Trivial, well-known evasion: an attacker (or an AI agent told to 'avoid the linter') splits the literal across adjacent lines via Python/JS implicit string concatenation or a backslash continuation, and the secret lands in the repo undetect…
- **Recommendation:** Add a multi-line scan pass for the high-value secret patterns (e.g. concatenate logical lines, or use grep -Pzo / pcregrep -M against a newline-tolerant variant). At minimum, document the per-line limitation prominently so consumers don't over-trust it.
- **Verifier note:** Finding is accurate. One scope note: the finder framed it as secrets-specific, but the identical per-physical-line `grep -nE` design in check-patterns.template shares the same limitation. Severity cor…

### ⬜ Open · `medium` — Test harness never exercises the CI (`--ci`) code path it claims is the unskippable backstop

- **Location:** `tests/run.sh:28-52,66-247`  ·  *(reproduced: yes, confidence: high, dimension: correctness-quality)*
- **What:** Every assertion in run.sh invokes `.githooks/pre-commit` (assert_rejects/assert_passes lines 30, 43; the MAX_LINES cases lines 177/191). The lib/check-* scripts are NEVER called with `--ci`, and the CI guardrails command (lint.yml.template lines 67-77: `git ls-files \| check-* --ci`) is never reproduced. The repo's own CI (test.yml) runs only run.sh + shellc…
- **Impact:** A regression that breaks only the `--ci` branch (the `::error file=` emission, the ls-files enumeration, exit aggregation in the guardrails step, or a future divergence in how CI feeds paths) would ship green. The marketed server-side enfor…
- **Recommendation:** Add harness cases that run `git ls-files \| .githooks/lib/check-* --ci` against the fixtures and assert both exit code and the `::error file=...::` output. Optionally add a workflow that renders and runs lint.yml against a fixture repo.
- **Verifier note:** Severity correctly set at medium. Clarify scope: this is a detection-efficacy / test-coverage gap, NOT a live exploitable bypass. The `--ci` path functions correctly today (I verified it emits annotat…

## ⚪ Low

| Status | Title | Location |
|---|---|---|
| 🟡 Partial | Distributed lint.yml frontend job executes attacker-controlled lifecycle scripts and eslint config from fork P… (now `npm ci --ignore-scripts` blocks pre/postinstall execution; eslint-config execution from PR head remains) | `lint.yml.template:41-58` |
| 🟡 Partial | All workflows trigger on bare `pull_request` with no concurrency control or runner hardening notes (now `persist-credentials: false` on every checkout; concurrency control still open) | `lint.yml.template:8-14` |
| ⬜ Open | actionlint binary downloaded via curl\|bash from a mutable git tag with no checksum/signature verification | `test.yml:33-36` |
| ✅ Fixed | README claims size check uses `wc -l`, but code uses `grep -c ''` (stale doc, contradicts CHANGELOG) | `README.md:186` |
| ✅ Fixed | Secrets-scan docs overstate coverage: README says 'all files', but lockfiles/binaries are skipped (now every tracked file IS scanned; doc corrected) | `README.md:188` |
| ⬜ Open | 'Hook and CI can never drift' claim is only true for the 4 lib checks; ruff/eslint are unshared, unpinned, and… | `README.md:6,39,104` |
| ✅ Fixed | File-scope asymmetry (hook=changed-only, CI=all-tracked) documented only for size, not for secrets/patterns/fi… | `README.md:223` |
| ⬜ Open | No CR-stripping, no .gitattributes, and no line-ending guidance for distributed config files | `README.md:1` |
| ⬜ Open | print/console.log/alert/os.path.join patterns fire inside comments and string literals (false positives); os.p… | `backend.txt.template:7-8` |
| ⬜ Open | AWS key coverage limited to AKIA; temporary (ASIA) and other AWS key-ID prefixes are not detected, contrary to… | `secrets.txt.template:13` |
| ⬜→✅ | URL-with-credentials pattern misses password-only userinfo (e.g. a redis URL with an empty user) — now FIXED, see "Fixed in follow-ups" above | `secrets.txt.template:25` |
| ⬜ Open | shell.txt curl\|bash and rm-rf/ patterns miss common real-world forms, overstating shell coverage | `shell.txt.template:4-5` |
| ✅ Fixed | check-filenames aborts on leading-dash filenames via unguarded basename (confusing failure, order-dependent) | `check-filenames.template:33` |
| ✅ Fixed | `printf \| head -3 \| sed` aborts check-patterns/check-secrets via SIGPIPE under pipefail (exit 141) | `check-patterns.template:92` |
| ⬜ Open | Pattern-validation oracle drops functional patterns on any stderr (warnings) and is grep-implementation/locale… | `check-patterns.template:48-56` |
| ✅ Fixed | Combined-ERE prefilter conflates grep error (exit 2) with no-match, skipping the file (fail-open control flow) | `check-patterns.template:81` |
| ✅ Fixed | Pattern-config description field is echoed unescaped into ::error workflow command (annotation spoofing in CI) — all four check-* scripts now percent-encode message + file= per GitHub workflow-command rules | `check-patterns.template:85-89` |
| ✅ Fixed | Committed filename containing `::` corrupts the file= property of every ::error annotation (file-target spoofing) — file= now percent-encodes `%`,CR,LF,`:`,`,` (fixture #35) | `check-patterns.template:89` |
| ✅ Fixed | Scan reads working-tree/index via filesystem, not the git blob — divergence between scanned bytes and committe… | `check-secrets.template:78-79` |
| ⬜ Open | scaffold-allow exempts an entire physical line — one marker hides multiple secrets on minified/single-line fil… | `check-secrets.template:83` |
| ⬜ Open | Case-insensitive secrets scan makes prefix tokens (AKIA, AIza, sk-, BEGIN PRIVATE KEY) match lowercase, enabli… | `check-secrets.template:79` |
| ⬜ Open | `.forbidden-patterns/` directory is exempt from the secret scan, so secrets hidden in pattern files are never… | `check-secrets.template:34` |
| ⬜ Open | Whitespace-only pattern column passes the `-z` guard and matches nearly every source file | `check-secrets.template:44` |
| ✅ Fixed | check-size silently passes oversized files whose name begins with `-` (MAX_LINES bypass) | `check-size.template:33-34` |
| ⬜ Open | check-size skips `.txt`/`.sql`/`.csv`, but check-secrets scans `.txt`/`.sql`/`.csv` — divergent skip lists und… | `check-size.template:28-29` |
| ⬜ Open | check-size counts physical lines (grep -c ''), so a multi-megabyte single-line blob trivially passes the MAX_L… | `check-size.template:33-34` |
| ✅ Fixed | stash pop conflict silently corrupts the working tree and strands unstaged work in a dangling stash | `pre-commit.template:56-61` |
| 🟡 Partial | Hook diff-filter ACMR omits type-changes (T); symlink content scanned differs from committed blob | `pre-commit.template:28` |
| ⬜ Open | source==destination guard defeated by symlinked scaffold path | `install.sh:15,34` |
| ⬜ Open | install.sh --force overwrites customized AGENTS.md / coding-rules.md / pattern files with no backup | `install.sh:57-66,71,80-92` |
| ⬜ Open | chmod +x runs on a skipped, user-modified hook making it executable | `install.sh:73-78` |
| ⬜ Open | cp_safe treats a directory at the destination as 'already installed' and skips it | `install.sh:57-66,75-78` |
| ⬜ Open | eslint smoke test only checks --version, never that eslint.config.js loads | `install.sh:135-142` |
| ⬜ Open | No test coverage for uninstall.sh, --force, --all, or hooksPath coexistence | `run.sh:63` |
| ⬜ Open | Reject-class tests assert only non-zero exit, not the reason — several could pass while the targeted check is… | `run.sh:28-39,68-130` |
| ⬜ Open | Pattern coverage untested: breakpoint/pdb/ipdb/os.path.join, debugger/alert, rm-rf/chmod have zero fixtures | `run.sh:80-123` |
| ⬜ Open | uninstall.sh reports 'unset' but leaves a global core.hooksPath=.githooks active | `uninstall.sh:94-102` |
| ⬜ Open | uninstall --all rm -rf .forbidden-patterns destroys user-added pattern files | `uninstall.sh:55-64,81` |

## ℹ️ Info

| Status | Title | Location |
|---|---|---|
| ⬜ Open | Action SHA pins verified accurate; no SHA-pin defects found in the four actions used | `lint.yml.template:26,33,45,52,65` |
| ⬜ Open | check-filenames only blocks dotfile-leading `.env*`; `foo.env` and arbitrary env files are not blocked | `check-filenames.template:34-39` |
| ✅ Fixed | Lint step passes staged filenames to ruff/eslint without `--`, allowing option injection via filename | `pre-commit.template:88` |
| ⬜ Open | core.hooksPath set with absent/partial pre-commit fails open (commits run unguarded) | `install.sh:98-109` |

## Rejected by adversarial verification

These candidates were surfaced by finders but **disproven** on verification (kept for transparency):

- GITHUB_OUTPUT / GITHUB_PATH writes are constant — no injection vector — This is a verification (negative) finding and its negative conclusion is correct. I read lint.yml.template and test.yml directly and grepped the entire .github/…
- Combined pre-filter ERE is built from unvalidated concatenation; alternation semantics diverge acros… — The finding's core claim — that ugrep 7.5.0 produces a false negative on the hardcoded-credential alternation pattern due to POSIX leftmost-longest semantics —…
- Combined ERE used as pre-filter is never validated, while individual patterns are — a consumer patte… — The code mechanism is read correctly: the combined ERE (check-patterns L63-71, check-secrets L68-75) is never validated, individual patterns are (L49/L57), and…
- Patterns relying on [0-9A-Z] are codepoint-based on modern GNU grep — locale/Unicode probe did NOT r… — The mechanism is real: forbidden-patterns/secrets.txt.template:13 uses AKIA[0-9A-Z]{16}, and the hook scripts (githooks/lib/check-secrets.template) set no LC_AL…
- scaffold-allow exemption does NOT prevent the combined-ERE hang — exempted lines still wedge the sca… — The finding has two parts. (1) The STRUCTURAL claim is true: in check-secrets.template the combined-ERE pre-filter at line 79 runs before the scaffold-allow fil…
- check-patterns shares the same combined-ERE pre-filter and is exposed to the same long-line blowup — The structural claim is accurate: githooks/lib/check-patterns.template (lines 63-71 build COMBINED='(p1)\|(p2)\|...', line 81 grep -nE pre-filter, line 86 per-p…

## Remediation roadmap (remaining work)

Grouped by root cause; ordered by leverage.

1. **Detection efficacy (Root Cause B)** — broaden patterns and add a multi-line pass: modern key prefixes (`sk-ant-`, `sk-proj-`, `github_pat_`), unquoted/YAML credential assignments, `curl -fsSL <url> | bash`, `rm -rf /*` and split/long-form flags, private-key *body* detection. **Strongly recommended:** layer a purpose-built secret scanner (gitleaks/trufflehog) as the secrets backstop — a per-line ERE is a hygiene tool, not a security boundary — and align the README's coverage claims with reality.
2. **Fail-closed config trust (Root Cause C/D)** — CI must error if `.forbidden-patterns/*.txt` is absent; refuse commits that delete/empty a pattern file; require a real TAB per pattern line; make `scaffold-allow` a strict end-of-line `# scaffold-allow` token (and consider not honoring it for secrets at all); escape `::error` annotation fields.
3. **CI/supply-chain** — pin the actionlint installer to a commit SHA + checksum (it's a `curl|bash` from a mutable tag); run the `guardrails` job's scanner/config from a **trusted base ref** so a fork PR can't neuter its own server-side check; document fork-PR lifecycle-script execution; set `lfs: true` (or scan blobs) for LFS consumers.
4. **ReDoS** — cap line length / file size before the combined-ERE pre-filter so a single long line can't hang the hook and CI.
5. **Test & docs integrity** — add `--ci`-path fixtures and per-pattern coverage fixtures; add uninstall/`--force`/`--all` tests; fix stale/overstated README claims (`wc -l` vs `grep -c ''`, "scans all files", "hook and CI can never drift"); ship `.gitattributes` + line-ending guidance for distributed config files.

---
*Generated from the audit run; full per-finding PoCs and verifier reasoning are in the workflow transcript.*
