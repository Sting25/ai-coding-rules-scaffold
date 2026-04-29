#!/usr/bin/env bash
# uninstall.sh — remove ai-coding-rules-scaffold files from the current project.
#
# Safe by default: only removes files whose content matches the scaffold's
# current templates byte-for-byte. Locally modified files are reported and
# left alone — edit or delete them yourself.
#
# Files considered "likely customized" (AGENTS.md, coding-rules.md,
# .forbidden-patterns/*.txt) are always left alone unless --all is given.
# CLAUDE.md is treated as a regenerable pointer and removed if unchanged.
#
# Usage:
#   uninstall.sh          # safe mode: only unchanged generated files
#   uninstall.sh --all    # also remove AGENTS.md / coding-rules.md / patterns
#   uninstall.sh --dry-run
#   uninstall.sh --help

set -euo pipefail

SCAFFOLD_DIR="$(cd "$(dirname "$0")" && pwd)"
DRY_RUN=0
REMOVE_ALL=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --all)     REMOVE_ALL=1 ;;
    --help|-h) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "error: unknown argument: $arg" >&2; exit 1 ;;
  esac
done

same_as_template() {
  # $1 = installed path, $2 = template path
  [ -f "$1" ] && [ -f "$2" ] && cmp -s "$1" "$2"
}

remove_if_unmodified() {
  local installed=$1 template=$2
  if [ ! -e "$installed" ]; then
    return
  fi
  if same_as_template "$installed" "$template"; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "would remove: $installed"
    else
      rm "$installed"
      echo "removed:      $installed"
    fi
  else
    echo "kept (modified): $installed — delete manually if you want it gone"
  fi
}

force_remove() {
  local path=$1
  [ -e "$path" ] || return
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "would remove: $path"
  else
    rm -rf "$path"
    echo "removed:      $path"
  fi
}

# Generated configs — removed only if unchanged
remove_if_unmodified "ruff.toml"                     "$SCAFFOLD_DIR/ruff.toml.template"
remove_if_unmodified "eslint.config.js"              "$SCAFFOLD_DIR/eslint.config.js.template"
remove_if_unmodified ".githooks/pre-commit"          "$SCAFFOLD_DIR/githooks/pre-commit.template"
for check in check-size check-patterns check-filenames check-secrets; do
  remove_if_unmodified ".githooks/lib/${check}" "$SCAFFOLD_DIR/githooks/lib/${check}.template"
done
remove_if_unmodified ".github/workflows/lint.yml"    "$SCAFFOLD_DIR/.github/workflows/lint.yml.template"
remove_if_unmodified "CLAUDE.md"                     "$SCAFFOLD_DIR/CLAUDE.md.pointer"

# Likely-customized files — only with --all
if [ "$REMOVE_ALL" -eq 1 ]; then
  force_remove "AGENTS.md"
  force_remove "coding-rules.md"
  force_remove ".forbidden-patterns"
fi

# Clean up empty dirs the installer created
for dir in .githooks/lib .githooks .github/workflows .github; do
  [ -d "$dir" ] || continue
  if rmdir "$dir" 2>/dev/null; then
    echo "removed empty: $dir"
  fi
done

# Unwire the hook
if [ -d .git ] && git config --get core.hooksPath >/dev/null 2>&1; then
  if [ "$(git config --get core.hooksPath)" = ".githooks" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "would unset:  core.hooksPath"
    else
      git config --unset core.hooksPath
      echo "unset:        core.hooksPath"
    fi
  fi
fi

echo ""
[ "$DRY_RUN" -eq 1 ] && echo "Dry run — no files changed." || echo "Done."
