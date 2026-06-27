#!/usr/bin/env bash
# install.sh — install ai-coding-rules-scaffold into the current project.
#
# Usage:
#   install.sh              # auto-detect Python/frontend based on project files
#   install.sh --python     # Python only
#   install.sh --frontend   # TS/JS only
#   install.sh --both       # install both stacks
#   install.sh --force      # replace scaffold files (backs each up first; never CLAUDE.md/AGENTS.md)
#   install.sh --no-verify  # skip the post-install linter smoke test
#   install.sh --claude     # also install opt-in Claude Code agent guardrails
#   install.sh --cursor     # also install opt-in Cursor agent guardrails (.cursor/hooks.json)
#   install.sh --commit-msg # also install the Conventional-Commits commit-msg hook
#   install.sh --gitleaks-hook # also install opt-in local gitleaks pre-commit pass
#   install.sh --all-langs  # install every language's forbidden-pattern file
#   install.sh --coverage-gate # also install the opt-in CI patch-coverage gate
#   install.sh --no-install # detect missing tools but never auto-run a package manager
#   install.sh --help       # show this help

set -euo pipefail

SCAFFOLD_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="auto"
FORCE=0
VERIFY=1
CLAUDE=0
CURSOR=0
COMMIT_MSG=0
GITLEAKS_HOOK=0
ALL_LANGS=0
COVERAGE_GATE=0
NO_INSTALL=0

for arg in "$@"; do
  case "$arg" in
    --python)     MODE="python" ;;
    --frontend)   MODE="frontend" ;;
    --both)       MODE="both" ;;
    --force)      FORCE=1 ;;
    --no-verify)  VERIFY=0 ;;
    --claude)     CLAUDE=1 ;;
    --cursor)     CURSOR=1 ;;
    --commit-msg) COMMIT_MSG=1 ;;
    --gitleaks-hook) GITLEAKS_HOOK=1 ;;
    --all-langs)  ALL_LANGS=1 ;;
    --coverage-gate) COVERAGE_GATE=1 ;;
    --no-install) NO_INSTALL=1 ;;
    --help|-h)    sed -n '2,18p' "$0"; exit 0 ;;
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
    echo "error: no pyproject.toml / requirements.txt / setup.py / package.json found." >&2
    echo "       Specify the stack explicitly: --python, --frontend, or --both." >&2
    exit 1
  fi
fi

cp_safe() {
  local src=$1 dst=$2
  if [ -e "$dst" ]; then
    if [ "$FORCE" -eq 0 ]; then
      echo "skip (exists): $dst  — left untouched (use --force to replace)"
      return
    fi
    # --force: back up the existing file before overwriting, but only when it
    # actually differs — so no edit is ever silently destroyed. Identical
    # files are a no-op.
    if cmp -s "$src" "$dst"; then
      return
    fi
    local bak="${dst}.scaffold-bak" n=0
    while [ -e "$bak" ]; do
      n=$((n + 1))
      if [ "$n" -gt 99 ]; then
        echo "error: too many .scaffold-bak files for $dst — clean some up" >&2
        return 1
      fi
      bak="${dst}.scaffold-bak.${n}"
    done
    cp "$dst" "$bak"
    echo "backed up:    $dst -> $bak"
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  echo "installed:    $dst"
}

# install_claude_md — CLAUDE.md is USER-OWNED project memory, not a scaffold
# file. Never replace it (not even with --force). If absent, create it from
# the pointer template. If present, append a marked block importing AGENTS.md
# once, and only if no @AGENTS.md import already exists.
install_claude_md() {
  if [ ! -e "CLAUDE.md" ]; then
    cp "$SCAFFOLD_DIR/CLAUDE.md.pointer" "CLAUDE.md"
    echo "installed:    CLAUDE.md (new — pointer to AGENTS.md)"
    return
  fi
  if grep -q '@AGENTS.md' "CLAUDE.md" 2>/dev/null \
     || grep -q 'ai-coding-rules-scaffold:begin' "CLAUDE.md" 2>/dev/null; then
    echo "ok (wired):   CLAUDE.md already imports AGENTS.md — left untouched"
    return
  fi
  {
    printf '\n<!-- ai-coding-rules-scaffold:begin -->\n'
    printf 'See [AGENTS.md](./AGENTS.md) — agent + project rules (cross-tool convention).\n\n'
    printf '@AGENTS.md\n'
    printf '<!-- ai-coding-rules-scaffold:end -->\n'
  } >>"CLAUDE.md"
  echo "merged:       appended @AGENTS.md import to existing CLAUDE.md (your content kept)"
}

# install_agents_md — AGENTS.md carries a Project section the user fills in,
# so an existing one is never clobbered (even with --force). Skip if present;
# create from template only when absent.
install_agents_md() {
  if [ -e "AGENTS.md" ]; then
    echo "skip (exists): AGENTS.md — left untouched (your Project section is safe)"
    return
  fi
  cp "$SCAFFOLD_DIR/AGENTS.md.template" "AGENTS.md"
  echo "installed:    AGENTS.md"
}

# Always
cp_safe "$SCAFFOLD_DIR/coding-rules.md" "coding-rules.md"
cp_safe "$SCAFFOLD_DIR/operational-rules.md" "operational-rules.md"
install_agents_md   # never clobbers an existing AGENTS.md
install_claude_md   # merges; never overwrites your CLAUDE.md
cp_safe "$SCAFFOLD_DIR/githooks/pre-commit.template" ".githooks/pre-commit"
chmod +x .githooks/pre-commit
# scaffold-config + scaffold-audit are the per-project override layer
# (.scaffold.toml): the check-* scripts source the former for per-rule
# disable / severity / per-path size caps; the latter lists active overrides.
for check in check-size check-patterns check-filenames check-secrets check-hygiene scaffold-config scaffold-audit; do
  cp_safe "$SCAFFOLD_DIR/githooks/lib/${check}.template" ".githooks/lib/${check}"
  chmod +x ".githooks/lib/${check}"
done
cp_safe "$SCAFFOLD_DIR/.github/workflows/lint.yml.template" ".github/workflows/lint.yml"
cp_safe "$SCAFFOLD_DIR/.github/dependabot.yml.template" ".github/dependabot.yml"
cp_safe "$SCAFFOLD_DIR/forbidden-patterns/secrets.txt.template" ".forbidden-patterns/secrets.txt"
cp_safe "$SCAFFOLD_DIR/forbidden-patterns/shell.txt.template" ".forbidden-patterns/shell.txt"
# Per-project override file — ships empty (all examples commented), so it
# enforces nothing until a team uncomments an entry. See scaffold-config.
cp_safe "$SCAFFOLD_DIR/.scaffold.toml.template" ".scaffold.toml"

# Python
if [ "$MODE" = "python" ] || [ "$MODE" = "both" ]; then
  cp_safe "$SCAFFOLD_DIR/ruff.toml.template" "ruff.toml"
  cp_safe "$SCAFFOLD_DIR/forbidden-patterns/backend.txt.template" ".forbidden-patterns/backend.txt"
  # Test-runner + coverage config (standalone, like ruff.toml — never edits
  # pyproject.toml). Skip pytest.ini if the project already configures pytest in
  # pyproject.toml/tox.ini/setup.cfg, since pytest.ini would silently override it.
  if grep -rqs -e '\[tool.pytest.ini_options\]' -e '\[pytest\]' pyproject.toml tox.ini setup.cfg 2>/dev/null; then
    echo "skip (pytest config exists): pytest.ini  — merge .coveragerc settings into your existing config"
  else
    cp_safe "$SCAFFOLD_DIR/pytest.ini.template" "pytest.ini"
  fi
  cp_safe "$SCAFFOLD_DIR/.coveragerc.template" ".coveragerc"
fi

# Frontend
if [ "$MODE" = "frontend" ] || [ "$MODE" = "both" ]; then
  cp_safe "$SCAFFOLD_DIR/eslint.config.js.template" "eslint.config.js"
  cp_safe "$SCAFFOLD_DIR/forbidden-patterns/frontend.txt.template" ".forbidden-patterns/frontend.txt"
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
  cp_safe "$SCAFFOLD_DIR/forbidden-patterns/${L}.txt.template" ".forbidden-patterns/${L}.txt"
done

# Agent-runtime guardrails (opt-in: --claude / --cursor). Both runtimes share
# one precheck script (it auto-detects the Claude vs Cursor payload shape), so
# install it once if either flag is set, then drop each runtime's config. An
# existing .claude/settings.json or .cursor/hooks.json is left alone by cp_safe —
# merge the template's keys in by hand.
if [ "$CLAUDE" -eq 1 ] || [ "$CURSOR" -eq 1 ]; then
  cp_safe "$SCAFFOLD_DIR/githooks/lib/agent-precheck.template" ".githooks/lib/agent-precheck"
  chmod +x ".githooks/lib/agent-precheck"
  if ! command -v jq >/dev/null 2>&1; then
    echo "warning: jq not found — the agent precheck needs jq (it fails open without it): https://jqlang.github.io/jq/"
  fi
fi
# Claude Code: settings.json adds a credential-file read deny-list plus the
# PreToolUse hook (matcher Write|Edit|MultiEdit|Bash).
if [ "$CLAUDE" -eq 1 ]; then
  cp_safe "$SCAFFOLD_DIR/claude-settings.json.template" ".claude/settings.json"
fi
# Cursor: hooks.json wires the same precheck to beforeShellExecution. Cursor has
# no before-write hook, so only the shell-command scan is portable here.
if [ "$CURSOR" -eq 1 ]; then
  cp_safe "$SCAFFOLD_DIR/cursor-hooks.json.template" ".cursor/hooks.json"
fi

# Conventional-Commits commit-msg hook (opt-in: --commit-msg). Active the moment
# it lands in core.hooksPath, so it's off by default to avoid surprising users.
if [ "$COMMIT_MSG" -eq 1 ]; then
  cp_safe "$SCAFFOLD_DIR/githooks/commit-msg.template" ".githooks/commit-msg"
  chmod +x ".githooks/commit-msg"
fi

# Local gitleaks pre-commit pass (opt-in: --gitleaks-hook). The pre-commit
# orchestrator runs lib/check-gitleaks only when the file exists, so installing
# it here is what turns it on. Kept opt-in because a local scan only fires where
# the gitleaks binary is present; pair it with gitleaks.yml.template in CI.
if [ "$GITLEAKS_HOOK" -eq 1 ]; then
  cp_safe "$SCAFFOLD_DIR/githooks/lib/check-gitleaks.template" ".githooks/lib/check-gitleaks"
  chmod +x ".githooks/lib/check-gitleaks"
  if ! command -v gitleaks >/dev/null 2>&1; then
    echo "warning: gitleaks not found — the local pass fails open (skips) until you install it: https://github.com/gitleaks/gitleaks#installing"
  fi
  echo "note: --gitleaks-hook is the LOCAL echo only. Add .github/workflows/gitleaks.yml (see gitleaks.yml.template) for the unskippable CI gate."
fi

# Opt-in CI patch-coverage gate (--coverage-gate). Fails a PR when CHANGED lines
# ship untested (diff-cover). Kept opt-in: it forces tests on new code, which is
# a policy choice a team must make deliberately. It gates EXECUTION of changed
# lines, not assertion quality — see RECOMMENDATIONS.md.
if [ "$COVERAGE_GATE" -eq 1 ]; then
  cp_safe "$SCAFFOLD_DIR/.github/workflows/coverage.yml.template" ".github/workflows/coverage.yml"
  echo "note: coverage.yml gates patch coverage (default 100% of changed lines)."
  echo "      It forces changed lines to be RUN by a test, not verified — pair with review."
fi

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

echo ""
echo "Done (mode: $MODE)."

# Post-install toolchain check — the scaffold ships CONFIGS and ENFORCEMENT, but
# the actual tools (ruff/eslint/tsc/prettier/test runner) are project deps. This
# step detects what's missing and OFFERS to install it. Auto-running a package
# manager only happens when SAFE: interactive TTY, not --no-verify, not in CI,
# and --no-install not set. Otherwise it just prints the command (the scaffold's
# prior, non-mutating behavior) so CI and piped/scripted runs never install.
CAN_AUTORUN=0
if [ "$VERIFY" -eq 1 ] && [ "$NO_INSTALL" -eq 0 ] && [ -t 0 ] && [ -z "${CI:-}" ]; then
  CAN_AUTORUN=1
fi

# Detect the project's package manager from lockfiles / available binaries.
js_install_cmd() {
  if [ -f pnpm-lock.yaml ] && command -v pnpm >/dev/null 2>&1; then echo "pnpm add -D"
  elif [ -f yarn.lock ] && command -v yarn >/dev/null 2>&1; then echo "yarn add -D"
  else echo "npm i -D"; fi
}
py_install_cmd() {
  if { [ -f uv.lock ] || grep -qs '\[tool.uv\]' pyproject.toml 2>/dev/null; } && command -v uv >/dev/null 2>&1; then
    echo "uv add --dev"
  else echo "pip install"; fi
}

# offer <label> <presence-test-command> <install-base> <packages>
# Prints ✓ when present; otherwise offers to install (auto-run only if safe).
offer() {
  local label=$1 testcmd=$2 base=$3 pkgs=$4 reply
  if eval "$testcmd" >/dev/null 2>&1; then
    echo "  ✓ $label installed"
    return
  fi
  if [ "$CAN_AUTORUN" -eq 1 ]; then
    printf "  ? %s not installed — install now with '%s %s'? [y/N] " "$label" "$base" "$pkgs"
    read -r reply || reply=""
    case "$reply" in
      [yY]|[yY][eE][sS])
        # shellcheck disable=SC2086  # word-split the package list deliberately
        if $base $pkgs; then echo "  ✓ $label installed"; else echo "  ✗ $label install failed — run: $base $pkgs"; fi ;;
      *) echo "  - skipped — run: $base $pkgs" ;;
    esac
  else
    echo "  ! $label not installed — run: $base $pkgs"
  fi
}

if [ "$VERIFY" -eq 1 ]; then
  echo ""
  echo "Checking toolchain (the scaffold configures these; you supply the binaries):"
  case "$MODE" in
    python|both)
      PYI=$(py_install_cmd)
      offer "ruff" "command -v ruff" "$PYI" "ruff"
      # ruff present: also confirm the config actually loads (2+ = config error).
      if command -v ruff >/dev/null 2>&1; then
        ruff_exit=0; ruff check --quiet . >/dev/null 2>&1 || ruff_exit=$?
        [ "$ruff_exit" -ge 2 ] && echo "  ✗ ruff config errored (exit $ruff_exit) — check ruff.toml"
      fi
      offer "pytest + coverage" "command -v pytest" "$PYI" "pytest pytest-cov"
      ;;
  esac
  case "$MODE" in
    frontend|both)
      JSI=$(js_install_cmd)
      offer "eslint" "npx --no-install eslint --version" "$JSI" "eslint @eslint/js typescript-eslint eslint-plugin-import-x eslint-plugin-unused-imports"
      offer "typescript (tsc)" "npx --no-install tsc --version" "$JSI" "typescript"
      offer "prettier" "npx --no-install prettier --version" "$JSI" "prettier"
      offer "vitest" "npx --no-install vitest --version" "$JSI" "vitest @vitest/coverage-v8"
      ;;
  esac
fi

echo ""
echo "Next:"
echo "  - Edit AGENTS.md — fill in the Project section at the bottom"
echo "  - Verify the hook: add 'print(\"x\")' to a .py file, 'git add' it, try to commit — hook should reject"
