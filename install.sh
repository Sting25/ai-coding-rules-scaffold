#!/usr/bin/env bash
# install.sh — install ai-coding-rules-scaffold into the current project.
#
# Usage:
#   install.sh              # auto-detect Python/frontend based on project files
#   install.sh --python     # Python only
#   install.sh --frontend   # TS/JS only
#   install.sh --both       # install both stacks
#   install.sh --shell      # shell-only project (hooks + shell/secrets patterns, no Python/TS configs)
#   install.sh --interactive # wizard: prompts for stack + each flag below (-i)
#   install.sh --force      # replace scaffold files (backs each up first; never CLAUDE.md/AGENTS.md)
#   install.sh --no-verify  # skip the post-install linter smoke test
#   install.sh --claude     # also install opt-in Claude Code agent guardrails
#   install.sh --cursor     # also install opt-in Cursor agent guardrails (.cursor/hooks.json)
#   install.sh --commit-msg # also install the Conventional-Commits commit-msg hook
#   install.sh --gitleaks-hook # also install opt-in local gitleaks pre-commit pass
#   install.sh --gitleaks-ci # also install the gitleaks CI workflow (unskippable gate)
#   install.sh --dependency-review # also install the dependency-review CI gate (opt-in: needs GitHub Advanced Security on a private repo, or it errors, so never default-on)
#   install.sh --zizmor-ci   # also install the zizmor GitHub Actions audit gate
#   install.sh --socket-ci   # also install the Socket Firewall supply-chain gate
#   install.sh --test-guard  # also install the red-green test-integrity gate (a new test must fail on the PR base before it may pass)
#   install.sh --npm-cooldown # also install .npmrc's min-release-age (delays newly published npm versions, needs npm >=11.10)
#   install.sh --claude-skill # also install an on-demand Claude Code Skill that loads coding-rules.md/operational-rules.md
#   install.sh --all-langs  # install every language's forbidden-pattern file
#   install.sh --coverage-gate # install the patch-coverage gate INSTEAD of the plain tests.yml (tests still run, plus a stricter check on top, see below)
#   install.sh --no-test-workflow # opt out of installing a test-execution CI workflow at all (records a loud skip; for repos that genuinely cannot run tests in CI)
#   install.sh --no-install # detect missing tools but never auto-run a package manager
#   install.sh --help       # show this help
#
# Test execution in CI is DEFAULT-ON (#97): a plain install writes `.github/workflows/tests.yml`
# so pytest/vitest run on every PR/push, no coverage threshold. `--coverage-gate` swaps that for
# `.github/workflows/coverage.yml` (same tests, plus a diff-cover patch-coverage gate), never both
# installed at once. Only `--no-test-workflow` leaves a repo with no test execution in CI, and it
# says so loudly in the summary below, per the "record every skip" rule.
#
# On re-run (upgrade): scaffold-owned code (the hook, .githooks/lib/*, the
# commit-msg hook) is REFRESHED when it differs from the shipped version, so
# security fixes reach you just by re-running, and every file it overwrites is
# BACKED UP to .scaffold-bak first, so an edit you made to one is recoverable
# and the "backed up:" line tells you it happened. User-owned configs are left
# alone. A drifted .forbidden-patterns/*.txt or CI workflow (lint.yml, tests.yml,
# coverage.yml, gitleaks.yml, dependency-review.yml, zizmor.yml, socket-security.yml,
# test-guard.yml)
# only prints a notice and keeps your file (--force replaces it, backed up first).
# .githooks/local.d/ is never written to at all: it's where project-local checks
# live precisely so an upgrade cannot unwire them.
#
# Every file this installer writes is recorded in .githooks/.scaffold-manifest
# (path, sha256 of exactly what was written, scaffold version). That is what
# lets a re-run tell an untouched file it wrote itself, which it REFRESHES, from
# one you edited, which it keeps and reports. Commit the manifest; see
# install-manifest.sh for the full model.

set -euo pipefail

SCAFFOLD_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="auto"
INTERACTIVE=0
FORCE=0
VERIFY=1
CLAUDE=0
CURSOR=0
COMMIT_MSG=0
GITLEAKS_HOOK=0
GITLEAKS_CI=0
DEPENDENCY_REVIEW=0
ZIZMOR_CI=0
SOCKET_CI=0
TEST_GUARD=0
NPM_COOLDOWN=0
CLAUDE_SKILL=0
ALL_LANGS=0
COVERAGE_GATE=0
NO_TEST_WORKFLOW=0
NO_INSTALL=0

for arg in "$@"; do
  case "$arg" in
    --python)     MODE="python" ;;
    --frontend)   MODE="frontend" ;;
    --both)       MODE="both" ;;
    --shell)      MODE="shell" ;;
    --interactive|-i) INTERACTIVE=1 ;;
    --force)      FORCE=1 ;;
    --no-verify)  VERIFY=0 ;;
    --claude)     CLAUDE=1 ;;
    --cursor)     CURSOR=1 ;;
    --commit-msg) COMMIT_MSG=1 ;;
    --gitleaks-hook) GITLEAKS_HOOK=1 ;;
    --gitleaks-ci) GITLEAKS_CI=1 ;;
    --dependency-review) DEPENDENCY_REVIEW=1 ;;
    --zizmor-ci)  ZIZMOR_CI=1 ;;
    --socket-ci)  SOCKET_CI=1 ;;
    --test-guard) TEST_GUARD=1 ;;
    --npm-cooldown) NPM_COOLDOWN=1 ;;
    --claude-skill) CLAUDE_SKILL=1 ;;
    --all-langs)  ALL_LANGS=1 ;;
    --coverage-gate) COVERAGE_GATE=1 ;;
    --no-test-workflow) NO_TEST_WORKFLOW=1 ;;
    --no-install) NO_INSTALL=1 ;;
    --help|-h)    sed -n '2,52p' "$0"; exit 0 ;;
    *) echo "error: unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# Guard against running inside the scaffold repo itself — source==destination
# on files like coding-rules.md would abort the script under `set -e`.
if [ "$(pwd -P)" = "$SCAFFOLD_DIR" ]; then
  echo "error: don't run install.sh from the scaffold directory itself." >&2
  echo "       cd into your target project and run the script from there." >&2
  exit 1
fi

# Auto-detect stack
if [ "$MODE" = "auto" ]; then
  HAS_PY=0
  HAS_JS=0
  { [ -f pyproject.toml ] || [ -f requirements.txt ] || [ -f setup.py ]; } && HAS_PY=1
  [ -f package.json ] && HAS_JS=1

  if   [ "$HAS_PY" -eq 1 ] && [ "$HAS_JS" -eq 1 ]; then MODE="both"
  elif [ "$HAS_PY" -eq 1 ]; then MODE="python"
  elif [ "$HAS_JS" -eq 1 ]; then MODE="frontend"
  else
    # No Python/JS manifest to key off. A shell-only project (plain bash/sh, no
    # package manager) has no equivalent manifest file, so fall back to looking
    # for shell scripts: tracked ones first — the same `git ls-files` fallback
    # the shipped lint.yml.template php job uses when there's no composer.json —
    # then the working tree, since install.sh is often run on a fresh project
    # before anything has been committed. A repo with neither still errors
    # rather than silently guessing a stack.
    #
    # Both probes avoid a pipeline on purpose: under `set -o pipefail` a
    # `... | grep -q .` reports the producer's SIGPIPE (141) when grep exits
    # early, which would read as "no shell scripts" and defeat the check.
    SH_HITS=""
    if git rev-parse --git-dir >/dev/null 2>&1; then
      SH_HITS=$(git ls-files -- '*.sh' '*.bash' 2>/dev/null || true)
    fi
    if [ -z "$SH_HITS" ]; then
      SH_HITS=$(find . -maxdepth 2 \( -name .git -o -name node_modules \) -prune -o \
                     -type f \( -name '*.sh' -o -name '*.bash' \) -print 2>/dev/null || true)
    fi
    if [ -n "$SH_HITS" ]; then
      MODE="shell"
    else
      echo "error: no pyproject.toml / requirements.txt / setup.py / package.json found," >&2
      echo "       and no *.sh/*.bash files either." >&2
      echo "       Specify the stack explicitly: --python, --frontend, --both, or --shell." >&2
      exit 1
    fi
  fi
fi

# --- file ownership & the install/upgrade model -----------------------------
# The install/upgrade policy helpers (cp_scaffold, cp_safe, cp_pattern,
# cp_scaffold_preserve, the shared _cp_replace / _backup mechanism where the
# A7 symlink defenses live, and mkx) are defined in install-lib.sh; see its
# own header comment for the full per-helper policy. SOURCED (not exec'd) so
# they run in this shell with its globals (FORCE) and `set -euo pipefail`.
# Extracted to keep this script under the scaffold's own 500-line cap.
# The install manifest (provenance: which files WE wrote, and at which version)
# is sourced FIRST, because install-lib.sh's copy policies call into it.
# shellcheck source=install-manifest.sh
. "$SCAFFOLD_DIR/install-manifest.sh"
# shellcheck source=install-lib.sh
. "$SCAFFOLD_DIR/install-lib.sh"

# shellcheck source=install-optin.sh
. "$SCAFFOLD_DIR/install-optin.sh"  # install_opt_in_* flag bodies

# shellcheck source=install-interactive.sh
. "$SCAFFOLD_DIR/install-interactive.sh"  # -i/--interactive wizard
# shellcheck source=install-claude.sh
. "$SCAFFOLD_DIR/install-claude.sh"  # install_claude_md / install_agents_md

# warn_pair_gap / warn_pair_note: install.sh's reporters for install-lib.sh's
# check_paired_artifacts (#96); advisory only, so both just print (install.sh
# never fails the run over one), matching scaffold-doctor.sh's wording for
# the same states, which DO carry a real exit-status difference there.
warn_pair_gap() {
  echo "warning: $1"
  echo "         fix: $2"
}
warn_pair_note() {
  echo "note: $1"
}

# -i/--interactive: prompt now, before any file is written.
if [ "$INTERACTIVE" -eq 1 ]; then
  run_interactive
fi

# Before anything can be backed up: teach .gitignore about the *.scaffold-bak
# copies this run may leave behind, so a routine `git add -A` never sweeps one
# into a commit (audit upgrade-path-2).
ensure_backup_gitignore

# Always
cp_safe "$SCAFFOLD_DIR/coding-rules.md" "coding-rules.md"
cp_safe "$SCAFFOLD_DIR/operational-rules.md" "operational-rules.md"
install_agents_md   # never clobbers an existing AGENTS.md
install_claude_md   # merges; never overwrites your CLAUDE.md
cp_scaffold "$SCAFFOLD_DIR/githooks/pre-commit.template" ".githooks/pre-commit"
mkx .githooks/pre-commit
# scaffold-config + scaffold-audit are the per-project override layer
# (.scaffold.toml): the check-* scripts source the former for per-rule
# disable / severity / per-path size caps; the latter lists active overrides.
# ci-changed-files scopes the CI quality gates to the PR/push diff (used by
# lint.yml so a fresh install doesn't retroactively fail pre-existing code).
# All scaffold-owned code → cp_scaffold so a re-run delivers security fixes.
for check in check-size check-large-files check-patterns check-filenames check-secrets check-hygiene scaffold-config scaffold-audit ci-changed-files; do
  cp_scaffold "$SCAFFOLD_DIR/githooks/lib/${check}.template" ".githooks/lib/${check}"
  mkx ".githooks/lib/${check}"
done
# lint.yml is the CI half of the local check contract, and a project commonly
# hand-edits it (adding setup steps for a local.d check): cp_scaffold_preserve
# so a plain re-run keeps that edit and notifies on drift instead of silently
# discarding it (#105); --force still replaces it, backed up first.
cp_scaffold_preserve "$SCAFFOLD_DIR/.github/workflows/lint.yml.template" ".github/workflows/lint.yml"
# .githooks/local.d/ — the project-local check extension point (#72). The
# DIRECTORY is user-owned territory: nothing here ever writes into it beyond
# this one README, and the README goes through cp_safe so even --force backs it
# up rather than discarding an edit. It is what makes the directory exist in a
# fresh install and, being tracked, survive a clone; it is not executable, so
# the hook's `-x` guard skips it. This is the whole point of the fix — pre-commit
# above is cp_scaffold (refreshed on upgrade, so a call site added there is
# reset), lint.yml above is cp_scaffold_preserve (#105: drift is kept, not
# reset), and anything in local.d/ is left strictly alone either way.
cp_safe "$SCAFFOLD_DIR/githooks/local.d/README.md.template" ".githooks/local.d/README.md"
# dependabot.yml is user-owned config (teams add their own ecosystems) → cp_safe.
cp_safe "$SCAFFOLD_DIR/.github/dependabot.yml.template" ".github/dependabot.yml"
# Pattern files are scaffold-shipped but user-extended → cp_pattern (notify on drift).
cp_pattern "$SCAFFOLD_DIR/forbidden-patterns/secrets.txt.template" ".forbidden-patterns/secrets.txt"
cp_pattern "$SCAFFOLD_DIR/forbidden-patterns/shell.txt.template" ".forbidden-patterns/shell.txt"
# Per-project override file — ships empty (all examples commented), so it
# enforces nothing until a team uncomments an entry. See scaffold-config.
cp_safe "$SCAFFOLD_DIR/.scaffold.toml.template" ".scaffold.toml"

# Python
if [ "$MODE" = "python" ] || [ "$MODE" = "both" ]; then
  cp_safe "$SCAFFOLD_DIR/ruff.toml.template" "ruff.toml"
  cp_pattern "$SCAFFOLD_DIR/forbidden-patterns/backend.txt.template" ".forbidden-patterns/backend.txt"
  # Test-runner + coverage config (standalone, like ruff.toml — never edits
  # pyproject.toml). Skip pytest.ini if the project already configures pytest,
  # since a root pytest.ini SILENTLY OVERRIDES that config: pytest picks one
  # ini-file, and the rootdir one wins.
  #
  # The root check alone was not enough (#76). `grep -r` does not recurse for a
  # FILE argument — only for a directory — so these three paths only ever looked
  # at the project root. In a monorepo the Python project lives in a subdirectory
  # (backend/, api/, services/x/) with its own [tool.pytest.ini_options], and the
  # root looked unconfigured. install.sh then wrote a root pytest.ini whose
  # `testpaths = tests` matched nothing, so pytest fell back to collecting from
  # rootdir — walking the whole tree into vendored toolchains and extra
  # checkouts — while shadowing the real config (losing e.g. asyncio_mode).
  # Inert AND shadowing is the worst of the three outcomes.
  #
  # So look one level down as well, bounded: -maxdepth 2 covers backend/ and
  # services/x/ without walking a vendored tree, and prunes the usual suspects.
  # A `find` result is only used as a yes/no signal, so a weird filename cannot
  # do anything but flip a boolean.
  PYTEST_CFG=""
  if grep -qs -e '\[tool.pytest.ini_options\]' -e '\[pytest\]' pyproject.toml tox.ini setup.cfg 2>/dev/null; then
    PYTEST_CFG="."
  else
    while IFS= read -r cand; do
      [ -n "$cand" ] || continue
      if grep -qs -e '\[tool.pytest.ini_options\]' -e '\[pytest\]' "$cand" 2>/dev/null; then
        PYTEST_CFG=$(dirname "$cand")
        break
      fi
    done <<EOF_PYCFG
$(find . -mindepth 2 -maxdepth 3 \
       \( -name .git -o -name node_modules -o -name .venv -o -name venv \
          -o -name .tox -o -name .claude -o -name vendor \) -prune -o \
       -type f \( -name pyproject.toml -o -name tox.ini -o -name setup.cfg -o -name pytest.ini \) \
       -print 2>/dev/null || true)
EOF_PYCFG
  fi
  if [ -n "$PYTEST_CFG" ]; then
    if [ "$PYTEST_CFG" = "." ]; then
      echo "skip (pytest config exists): pytest.ini  — merge .coveragerc settings into your existing config"
    else
      echo "skip (pytest config in ${PYTEST_CFG#./}): pytest.ini  — not writing a root pytest.ini; a root ini overrides the one in ${PYTEST_CFG#./} and would collect the whole tree. Run pytest from ${PYTEST_CFG#./}, and merge .coveragerc settings into that config."
    fi
  else
    cp_safe "$SCAFFOLD_DIR/pytest.ini.template" "pytest.ini"
    # Installed a root pytest.ini but there is no root tests/ for its
    # `testpaths = tests` to match. pytest treats an unmatched testpaths as
    # "collect from rootdir", so the config that looks scoped is really
    # whole-tree. Say so at install time rather than letting them find out via a
    # collection error from a vendored package.
    if [ ! -d tests ]; then
      echo "note:         pytest.ini installed but ./tests/ does not exist — its 'testpaths = tests' matches nothing, and pytest then collects from the repo root. Create ./tests/, or point testpaths at your real test dir."
    fi
  fi
  cp_safe "$SCAFFOLD_DIR/.coveragerc.template" ".coveragerc"
fi

# Frontend
if [ "$MODE" = "frontend" ] || [ "$MODE" = "both" ]; then
  cp_safe "$SCAFFOLD_DIR/eslint.config.js.template" "eslint.config.js"
  cp_pattern "$SCAFFOLD_DIR/forbidden-patterns/frontend.txt.template" ".forbidden-patterns/frontend.txt"
  # TypeScript config the eslint type-aware rules + the tsc --noEmit hook/CI
  # step already assume (closes the gap where they silently degrade if absent).
  cp_safe "$SCAFFOLD_DIR/tsconfig.json.template" "tsconfig.json"
  # Formatting: Prettier runs SEPARATELY from eslint by design (strictTypeChecked
  # ships no stylistic rules, so there is no eslint-config-prettier — see the
  # header of eslint.config.js).
  cp_safe "$SCAFFOLD_DIR/.prettierrc.json.template" ".prettierrc.json"
  cp_safe "$SCAFFOLD_DIR/.prettierignore.template" ".prettierignore"
  # Test runner: default to Vitest, but don't fight a project already on Jest.
  if grep -qs '"jest"' package.json 2>/dev/null || ls -1 jest.config.* >/dev/null 2>&1; then
    echo "skip (Jest detected): vitest.config.ts  — keep Jest; ensure it emits cobertura coverage for the gate"
  else
    cp_safe "$SCAFFOLD_DIR/vitest.config.ts.template" "vitest.config.ts"
  fi
fi

# Additional language pattern files (config-driven check-patterns). Each ships a
# `<lang>.txt` with a `# scaffold-extensions:` header that check-patterns auto-
# discovers — so adding a language is just dropping a file. Installed when the
# language's manifest is detected, or all of them with --all-langs.
LANGS=""
add_lang() { case " $LANGS " in *" $1 "*) ;; *) LANGS="$LANGS $1" ;; esac; }
if [ "$ALL_LANGS" -eq 1 ]; then
  for L in php go rust java kotlin ruby; do add_lang "$L"; done
else
  if [ -f composer.json ]; then add_lang php; fi
  if [ -f go.mod ]; then add_lang go; fi
  if [ -f Cargo.toml ]; then add_lang rust; fi
  if [ -f pom.xml ] || [ -f build.gradle ]; then add_lang java; fi
  if [ -f build.gradle.kts ] || ls -1 ./*.kt >/dev/null 2>&1; then add_lang kotlin; fi
  if [ -f Gemfile ] || ls -1 ./*.gemspec >/dev/null 2>&1; then add_lang ruby; fi
fi
for L in $LANGS; do
  cp_pattern "$SCAFFOLD_DIR/forbidden-patterns/${L}.txt.template" ".forbidden-patterns/${L}.txt"
done

# Agent-runtime guardrails (opt-in: --claude / --cursor). Both runtimes share
# one precheck script (it auto-detects the Claude vs Cursor payload shape), so
# install it once if either flag is set, then drop each runtime's config. An
# existing .claude/settings.json or .cursor/hooks.json is left alone by cp_safe —
# merge the template's keys in by hand.
if [ "$CLAUDE" -eq 1 ] || [ "$CURSOR" -eq 1 ]; then
  cp_scaffold "$SCAFFOLD_DIR/githooks/lib/agent-precheck.template" ".githooks/lib/agent-precheck"
  mkx ".githooks/lib/agent-precheck"
  if ! command -v jq >/dev/null 2>&1; then
    echo "warning: jq not found — the agent precheck needs jq (it fails open without it): https://jqlang.github.io/jq/"
  fi
fi
# Claude Code: settings.json adds a credential-file read deny-list plus the
# PreToolUse hook (matcher Write|Edit|MultiEdit|Bash).
if [ "$CLAUDE" -eq 1 ]; then
  cp_safe "$SCAFFOLD_DIR/claude-settings.json.template" ".claude/settings.json"
  warn_unwired_optin ".claude/settings.json" agent-precheck "$SCAFFOLD_DIR/claude-settings.json.template"
fi
# Cursor: hooks.json wires beforeShellExecution + beforeReadFile (credential-path deny); no before-write hook, so secret-on-write stays unportable here.
if [ "$CURSOR" -eq 1 ]; then
  cp_safe "$SCAFFOLD_DIR/cursor-hooks.json.template" ".cursor/hooks.json"
  warn_unwired_optin ".cursor/hooks.json" agent-precheck "$SCAFFOLD_DIR/cursor-hooks.json.template"
  cp_pattern "$SCAFFOLD_DIR/githooks/lib/credential-read-patterns.txt.template" ".githooks/lib/credential-read-patterns.txt"
fi

# Conventional-Commits commit-msg hook (opt-in: --commit-msg). Active the moment
# it lands in core.hooksPath, so it's off by default to avoid surprising users.
if [ "$COMMIT_MSG" -eq 1 ]; then
  cp_scaffold "$SCAFFOLD_DIR/githooks/commit-msg.template" ".githooks/commit-msg"
  mkx ".githooks/commit-msg"
fi

# Local gitleaks pre-commit pass (opt-in: --gitleaks-hook). The pre-commit
# orchestrator runs lib/check-gitleaks only when the file exists, so installing
# it here is what turns it on. Kept opt-in because a local scan only fires where
# the gitleaks binary is present; pair it with gitleaks.yml.template in CI.
if [ "$GITLEAKS_HOOK" -eq 1 ]; then
  cp_scaffold "$SCAFFOLD_DIR/githooks/lib/check-gitleaks.template" ".githooks/lib/check-gitleaks"
  mkx ".githooks/lib/check-gitleaks"
  if ! command -v gitleaks >/dev/null 2>&1; then
    echo "warning: gitleaks not found — the local pass fails open (skips) until you install it: https://github.com/gitleaks/gitleaks#installing"
  fi
  echo "note: --gitleaks-hook is the LOCAL pass only. Add --gitleaks-ci for the unskippable CI gate (.github/workflows/gitleaks.yml)."
fi

# Opt-in gitleaks CI workflow (--gitleaks-ci). The unskippable server-side gate
# that pairs with --gitleaks-hook's local pass. A dedicated flag (mirroring
# --coverage-gate) actually INSTALLS the workflow, so npx users (who have no
# persistent copy of gitleaks.yml.template on disk) can wire the CI gate too.
# cp_scaffold_preserve, not cp_scaffold (#110, same drift-preserving policy as
# lint.yml since #105): a re-run keeps a hand-edited or pre-existing
# gitleaks.yml and prints a drift note instead of silently overwriting it.
if [ "$GITLEAKS_CI" -eq 1 ]; then
  cp_scaffold_preserve "$SCAFFOLD_DIR/.github/workflows/gitleaks.yml.template" ".github/workflows/gitleaks.yml"
  echo "note: gitleaks.yml is the unskippable CI secret scan (runs even without --no-verify locally)."
fi

# Opt-in dependency-review CI gate (--dependency-review, #113). Same shape as
# --gitleaks-ci above: a dedicated flag actually INSTALLS the workflow via
# cp_scaffold_preserve, so a re-run keeps a hand-edited or pre-existing
# dependency-review.yml and prints a drift note instead of silently
# overwriting it; --force replaces it, backed up first. Kept opt-in rather
# than default-on because dependency-review-action needs GitHub's Dependency
# Graph: on by default for public repos, but it ERRORS on a private repo
# without GitHub Advanced Security, so a default-on install would break CI
# for private-repo consumers without GHAS.
if [ "$DEPENDENCY_REVIEW" -eq 1 ]; then
  cp_scaffold_preserve "$SCAFFOLD_DIR/.github/workflows/dependency-review.yml.template" ".github/workflows/dependency-review.yml"
  echo "note: dependency-review.yml needs GitHub's Dependency Graph (on by default for public repos; needs GitHub Advanced Security for private repos, or it errors)."
fi

# Opt-in zizmor / Socket Firewall CI gates (--zizmor-ci, --socket-ci), npm
# install-layer cooldown (--npm-cooldown, #117), Claude Skill packaging
# (--claude-skill, #118), and the red-green test-integrity gate
# (--test-guard, #140); function bodies live in install-optin.sh to keep this
# file and install-lib.sh under their 500-line caps (issue #84).
install_opt_in_zizmor_ci
install_opt_in_socket_ci
install_opt_in_test_guard
install_opt_in_npm_cooldown
install_opt_in_claude_skill

# Test-execution CI workflow (#97): DEFAULT-ON, exactly one of two shapes,
# plus a recorded opt-out (--no-test-workflow). See install-optin.sh's
# install_test_workflow_ci for the full decision order and rationale; it sets
# TEST_CI_STATE for the summary near the end of this script.
install_test_workflow_ci

# Wire the hook — preserve existing core.hooksPath if already set (e.g. Husky).
# Use `git rev-parse --git-dir` so this works in worktrees (where .git is a
# file, not a directory) and submodules.
if git rev-parse --git-dir >/dev/null 2>&1; then
  EXISTING_HOOKS_PATH=$(git config --get core.hooksPath || true)
  if [ -z "$EXISTING_HOOKS_PATH" ] || [ "$EXISTING_HOOKS_PATH" = ".githooks" ]; then
    git config core.hooksPath .githooks
    echo "configured:   core.hooksPath = .githooks"
  else
    echo "warning: core.hooksPath is already '$EXISTING_HOOKS_PATH' — leaving it alone."
    echo "         Point it at .githooks or chain our hook into your existing setup."
  fi
else
  echo "warning: not in a git repo — run 'git config core.hooksPath .githooks' after 'git init'"
fi

# Write the install manifest: one line per file this run wrote, carrying the
# sha256 of exactly those bytes plus this scaffold's version. Runs after every
# write and before the summaries, so the next upgrade can tell what it wrote
# itself from what the project has since edited (install-manifest.sh).
manifest_flush

# Paired-artifact consistency check (#96): install.sh can leave a config half
# without its CI-enforcement half if an earlier run used a different flag
# set, or a file was hand-copied in isolation, and nothing used to check
# again after the run finished. Runs last, once everything THIS run would
# write is already on disk; advisory only, so it never changes install.sh's
# own exit status. Same detection + wording scaffold-doctor.sh reports later,
# from install-lib.sh's check_paired_artifacts.
check_paired_artifacts warn_pair_gap warn_pair_note

echo ""
echo "Done (mode: $MODE)."
echo "CI test state: $TEST_CI_STATE"

# Post-install toolchain check — the scaffold ships CONFIGS and ENFORCEMENT, but
# the actual tools (ruff/eslint/tsc/prettier/test runner) are project deps. That
# whole step lives in install-verify.sh, extracted from this file at the
# scaffold's own 500-line module cap (issue #84); SOURCED-not-exec'd like
# install-lib.sh above, so it runs here with MODE/VERIFY/NO_INSTALL in scope.
# shellcheck source=install-verify.sh
. "$SCAFFOLD_DIR/install-verify.sh"
run_toolchain_verify

echo ""
echo "Next:"
echo "  - Edit AGENTS.md — fill in the Project section at the bottom"
case "$MODE" in
  # Literal split (`7`+`77`) so this .sh file does not itself carry the pattern
  # shell.txt forbids — the scaffold's own guardrails scan install.sh. The echo
  # still prints the contiguous string; same trick the test harness uses.
  shell) echo "  - Verify the hook: add 'chmod 7""77 /tmp/x' to a .sh file, 'git add' it, try to commit — hook should reject" ;;
  frontend) echo "  - Verify the hook: add 'console.log(\"x\")' to a .ts file, 'git add' it, try to commit — hook should reject" ;;
  *) echo "  - Verify the hook: add 'print(\"x\")' to a .py file, 'git add' it, try to commit — hook should reject" ;;
esac
print_history_scan_note; print_not_enabled_summary

# A symlinked scaffold DIRECTORY (.githooks, .github, .claude, .cursor) makes
# every write under it a refusal in _mkdir_safe, so this run really did not
# install what it was asked to: name the paths once and FAIL, rather than
# exiting 0 over a half-written install (audit code-install-policy-2).
print_refused_writes_summary || exit 1
