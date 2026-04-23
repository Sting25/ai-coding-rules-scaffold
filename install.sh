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
#   install.sh --help       # show this help

set -euo pipefail

SCAFFOLD_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="auto"
FORCE=0
VERIFY=1

for arg in "$@"; do
  case "$arg" in
    --python)    MODE="python" ;;
    --frontend)  MODE="frontend" ;;
    --both)      MODE="both" ;;
    --force)     FORCE=1 ;;
    --no-verify) VERIFY=0 ;;
    --help|-h)   sed -n '2,11p' "$0"; exit 0 ;;
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
cp_safe "$SCAFFOLD_DIR/AGENTS.md.template" "AGENTS.md"
cp_safe "$SCAFFOLD_DIR/CLAUDE.md.pointer" "CLAUDE.md"
cp_safe "$SCAFFOLD_DIR/githooks/pre-commit.template" ".githooks/pre-commit"
chmod +x .githooks/pre-commit
cp_safe "$SCAFFOLD_DIR/.github/workflows/lint.yml.template" ".github/workflows/lint.yml"
cp_safe "$SCAFFOLD_DIR/forbidden-patterns/secrets.txt.template" ".forbidden-patterns/secrets.txt"

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

# Wire the hook — preserve existing core.hooksPath if already set (e.g. Husky)
if [ -d .git ]; then
  EXISTING_HOOKS_PATH=$(git config --get core.hooksPath || true)
  if [ -z "$EXISTING_HOOKS_PATH" ] || [ "$EXISTING_HOOKS_PATH" = ".githooks" ]; then
    git config core.hooksPath .githooks
    echo "configured:   core.hooksPath = .githooks"
  else
    echo "warning: core.hooksPath is already '$EXISTING_HOOKS_PATH' — leaving it alone."
    echo "         Point it at .githooks or chain our hook into your existing setup."
  fi
else
  echo "warning: no .git directory — run 'git config core.hooksPath .githooks' after 'git init'"
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
        if ruff check --quiet --exit-zero . >/dev/null 2>&1; then
          echo "  ✓ ruff installed and config loads"
        else
          echo "  ✗ ruff installed but 'ruff check' errored — check ruff.toml"
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
        echo "  ! eslint not installed — run: npm i -D eslint @eslint/js typescript-eslint"
      fi ;;
  esac
fi

echo ""
echo "Next:"
echo "  - Edit AGENTS.md — fill in the Project section at the bottom"
echo "  - Verify the hook: add 'print(\"x\")' to a .py file, 'git add' it, try to commit — hook should reject"
