#!/usr/bin/env bash
# install.sh — install ai-coding-rules-scaffold into the current project.
#
# Usage:
#   install.sh              # auto-detect Python/frontend based on project files
#   install.sh --python     # Python only
#   install.sh --frontend   # TS/JS only
#   install.sh --both       # install both stacks
#   install.sh --force      # overwrite existing files
#   install.sh --no-verify  # skip the post-install linter smoke test
#   install.sh --claude     # also install opt-in Claude Code agent guardrails
#   install.sh --cursor     # also install opt-in Cursor agent guardrails (.cursor/hooks.json)
#   install.sh --commit-msg # also install the Conventional-Commits commit-msg hook
#   install.sh --gitleaks-hook # also install opt-in local gitleaks pre-commit pass
#   install.sh --all-langs  # install every language's forbidden-pattern file
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
    --help|-h)    sed -n '2,16p' "$0"; exit 0 ;;
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
  if [ -e "$dst" ] && [ "$FORCE" -eq 0 ]; then
    echo "skip (exists): $dst  — use --force to overwrite"
    return
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  echo "installed:    $dst"
}

# Always
cp_safe "$SCAFFOLD_DIR/coding-rules.md" "coding-rules.md"
cp_safe "$SCAFFOLD_DIR/operational-rules.md" "operational-rules.md"
cp_safe "$SCAFFOLD_DIR/AGENTS.md.template" "AGENTS.md"
cp_safe "$SCAFFOLD_DIR/CLAUDE.md.pointer" "CLAUDE.md"
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
fi

# Frontend
if [ "$MODE" = "frontend" ] || [ "$MODE" = "both" ]; then
  cp_safe "$SCAFFOLD_DIR/eslint.config.js.template" "eslint.config.js"
  cp_safe "$SCAFFOLD_DIR/forbidden-patterns/frontend.txt.template" ".forbidden-patterns/frontend.txt"
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

# Post-install smoke test — confirms linters are installed and configs load.
if [ "$VERIFY" -eq 1 ]; then
  echo ""
  echo "Verifying linters:"
  case "$MODE" in
    python|both)
      if command -v ruff >/dev/null 2>&1; then
        # Explicit exit-code handling so the smoke test actually distinguishes
        # "config parsed cleanly" from "ruff crashed on a bad config".
        # ruff: 0 = no issues, 1 = lint issues found, 2+ = config/invocation error.
        ruff_exit=0
        ruff check --quiet . >/dev/null 2>&1 || ruff_exit=$?
        if [ "$ruff_exit" -le 1 ]; then
          echo "  ✓ ruff installed and config loads"
        else
          echo "  ✗ ruff installed but config errored (exit $ruff_exit) — check ruff.toml"
        fi
      else
        echo "  ! ruff not installed — run: pip install ruff"
      fi ;;
  esac
  case "$MODE" in
    frontend|both)
      if command -v npx >/dev/null 2>&1 && npx --no-install eslint --version >/dev/null 2>&1; then
        echo "  ✓ eslint installed"
      else
        echo "  ! eslint not installed — run: npm i -D eslint @eslint/js typescript-eslint eslint-plugin-import-x eslint-plugin-unused-imports"
      fi ;;
  esac
fi

echo ""
echo "Next:"
echo "  - Edit AGENTS.md — fill in the Project section at the bottom"
echo "  - Verify the hook: add 'print(\"x\")' to a .py file, 'git add' it, try to commit — hook should reject"
