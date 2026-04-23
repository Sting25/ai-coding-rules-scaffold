#!/usr/bin/env bash
# install.sh — install coding-rules-scaffold into the current project.
#
# Usage:
#   install.sh              # auto-detect Python/frontend based on project files
#   install.sh --python     # Python only
#   install.sh --frontend   # TS/JS only
#   install.sh --both       # install both stacks
#   install.sh --force      # overwrite existing files
#   install.sh --help       # show this help

set -euo pipefail

SCAFFOLD_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="auto"
FORCE=0

for arg in "$@"; do
  case "$arg" in
    --python)   MODE="python" ;;
    --frontend) MODE="frontend" ;;
    --both)     MODE="both" ;;
    --force)    FORCE=1 ;;
    --help|-h)  sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "error: unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# Auto-detect stack
if [ "$MODE" = "auto" ]; then
  HAS_PY=0
  HAS_JS=0
  { [ -f pyproject.toml ] || [ -f requirements.txt ] || [ -f setup.py ]; } && HAS_PY=1
  [ -f package.json ] && HAS_JS=1

  if   [ "$HAS_PY" -eq 1 ] && [ "$HAS_JS" -eq 1 ]; then MODE="both"
  elif [ "$HAS_PY" -eq 1 ]; then MODE="python"
  elif [ "$HAS_JS" -eq 1 ]; then MODE="frontend"
  else MODE="python"; echo "note: no pyproject.toml / package.json — defaulting to Python"
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
cp_safe "$SCAFFOLD_DIR/coding-rules.md" ".claude/coding-rules.md"
cp_safe "$SCAFFOLD_DIR/githooks/pre-commit.template" ".githooks/pre-commit"
chmod +x .githooks/pre-commit

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

# Wire the hook
if [ -d .git ]; then
  git config core.hooksPath .githooks
  echo "configured:   core.hooksPath = .githooks"
else
  echo "warning: no .git directory — run 'git config core.hooksPath .githooks' after 'git init'"
fi

echo ""
echo "Done (mode: $MODE). Next steps:"
case "$MODE" in
  python|both)   echo "  - Install ruff:    pip install ruff" ;;
esac
case "$MODE" in
  frontend|both) echo "  - Install eslint:  npm i -D eslint @eslint/js typescript-eslint" ;;
esac
echo "  - Reference .claude/coding-rules.md from your CLAUDE.md (or equivalent AI agent config)"
echo "  - Verify: add 'print(\"x\")' to a .py file, 'git add' it, try to commit — hook should reject"
