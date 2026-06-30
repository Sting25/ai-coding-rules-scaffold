#!/usr/bin/env bash
# uninstall.sh — remove ai-coding-rules-scaffold files from the current project.
#
# Safe by default: only removes files whose content matches the scaffold's
# current templates byte-for-byte. Locally modified files are reported and
# left alone — edit or delete them yourself.
#
# Files considered "likely customized" (AGENTS.md, coding-rules.md,
# .forbidden-patterns/*.txt) are always left alone unless --all is given.
# CLAUDE.md is user-owned — only a scaffold-created file or our appended block is removed.
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

# clean_claude_md — CLAUDE.md is user-owned. If we created it wholesale
# (byte-equal to the pointer template), remove it. If we appended our marked
# import block to the user's own file, strip ONLY that block and keep the
# rest. Otherwise leave it entirely alone. Never deletes user content.
clean_claude_md() {
  [ -e "CLAUDE.md" ] || return
  if same_as_template "CLAUDE.md" "$SCAFFOLD_DIR/CLAUDE.md.pointer"; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "would remove: CLAUDE.md (scaffold-created pointer)"
    else
      rm "CLAUDE.md"
      echo "removed:      CLAUDE.md (scaffold-created pointer)"
    fi
    return
  fi
  # Strip our marked block ONLY when BOTH delimiters are present. A lone begin
  # marker (the user edited the block away, or a prior install was interrupted
  # between the two printfs) would make an open-ended `/begin/,/end/d` delete
  # run to END OF FILE and silently eat the user's content below it — the exact
  # data-loss class this scaffold exists to prevent. In that case leave the
  # file untouched and say so.
  local has_begin=0 has_end=0
  if grep -q '<!-- ai-coding-rules-scaffold:begin -->' "CLAUDE.md" 2>/dev/null; then has_begin=1; fi
  if grep -q '<!-- ai-coding-rules-scaffold:end -->'   "CLAUDE.md" 2>/dev/null; then has_end=1; fi
  if [ "$has_begin" -eq 1 ] && [ "$has_end" -eq 1 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "would strip:  scaffold import block from CLAUDE.md (your content kept)"
    else
      # awk (portable across BSD/GNU) deletes the begin..end block plus the one
      # immediately-preceding blank line install.sh inserts as a spacer, so a
      # round-trip leaves no residue. The delete is bounded by the end marker,
      # never to EOF. Write to a temp and mv only on success — the original is
      # never edited in place, so a failure can't truncate it.
      if awk '
        $0 == "" && !inblock { if (pend) print hold; hold = $0; pend = 1; next }
        index($0, "<!-- ai-coding-rules-scaffold:begin -->") { inblock = 1; pend = 0; next }
        index($0, "<!-- ai-coding-rules-scaffold:end -->")   { inblock = 0; next }
        { if (inblock) next; if (pend) { print hold; pend = 0 } print }
        END { if (pend) print hold }
      ' "CLAUDE.md" >"CLAUDE.md.scaffold-tmp"; then
        mv "CLAUDE.md.scaffold-tmp" "CLAUDE.md"
        echo "stripped:     scaffold import block from CLAUDE.md (your content kept)"
      else
        rm -f "CLAUDE.md.scaffold-tmp"
        echo "error:        failed to rewrite CLAUDE.md — left untouched" >&2
        return 1
      fi
    fi
    return
  fi
  if [ "$has_begin" -eq 1 ]; then
    echo "kept:         CLAUDE.md — scaffold block incomplete (no end marker), left untouched"
    return
  fi
  echo "kept:         CLAUDE.md — no scaffold block found, left untouched"
}

# Generated configs — removed only if unchanged
remove_if_unmodified "ruff.toml"                     "$SCAFFOLD_DIR/ruff.toml.template"
remove_if_unmodified "pytest.ini"                    "$SCAFFOLD_DIR/pytest.ini.template"
remove_if_unmodified ".coveragerc"                   "$SCAFFOLD_DIR/.coveragerc.template"
remove_if_unmodified "eslint.config.js"              "$SCAFFOLD_DIR/eslint.config.js.template"
remove_if_unmodified "tsconfig.json"                 "$SCAFFOLD_DIR/tsconfig.json.template"
remove_if_unmodified ".prettierrc.json"              "$SCAFFOLD_DIR/.prettierrc.json.template"
remove_if_unmodified ".prettierignore"               "$SCAFFOLD_DIR/.prettierignore.template"
remove_if_unmodified "vitest.config.ts"              "$SCAFFOLD_DIR/vitest.config.ts.template"
remove_if_unmodified ".githooks/pre-commit"          "$SCAFFOLD_DIR/githooks/pre-commit.template"
for check in check-size check-patterns check-filenames check-secrets check-hygiene scaffold-config scaffold-audit ci-changed-files; do
  remove_if_unmodified ".githooks/lib/${check}" "$SCAFFOLD_DIR/githooks/lib/${check}.template"
done
# Per-project override file — removed only if still byte-identical to the
# shipped (empty) template; a team that has recorded overrides keeps it.
remove_if_unmodified ".scaffold.toml"                "$SCAFFOLD_DIR/.scaffold.toml.template"
remove_if_unmodified ".github/workflows/lint.yml"    "$SCAFFOLD_DIR/.github/workflows/lint.yml.template"
remove_if_unmodified ".github/dependabot.yml"        "$SCAFFOLD_DIR/.github/dependabot.yml.template"
clean_claude_md
# Opt-in Claude Code guardrails (only present if installed with --claude).
remove_if_unmodified ".githooks/lib/agent-precheck"  "$SCAFFOLD_DIR/githooks/lib/agent-precheck.template"
remove_if_unmodified ".claude/settings.json"         "$SCAFFOLD_DIR/claude-settings.json.template"
# Opt-in Cursor guardrails (only present if installed with --cursor).
remove_if_unmodified ".cursor/hooks.json"            "$SCAFFOLD_DIR/cursor-hooks.json.template"
# Opt-in commit-msg hook (only present if installed with --commit-msg).
remove_if_unmodified ".githooks/commit-msg"          "$SCAFFOLD_DIR/githooks/commit-msg.template"
# Opt-in local gitleaks pass (only present if installed with --gitleaks-hook).
remove_if_unmodified ".githooks/lib/check-gitleaks"  "$SCAFFOLD_DIR/githooks/lib/check-gitleaks.template"
# Opt-in CI patch-coverage gate (only present if installed with --coverage-gate).
remove_if_unmodified ".github/workflows/coverage.yml" "$SCAFFOLD_DIR/.github/workflows/coverage.yml.template"

# Likely-customized files — only with --all
if [ "$REMOVE_ALL" -eq 1 ]; then
  force_remove "AGENTS.md"
  force_remove "coding-rules.md"
  force_remove "operational-rules.md"
  force_remove ".forbidden-patterns"
fi

# Clean up empty dirs the installer created
for dir in .githooks/lib .githooks .github/workflows .github .claude .cursor; do
  [ -d "$dir" ] || continue
  if rmdir "$dir" 2>/dev/null; then
    echo "removed empty: $dir"
  fi
done

# Unwire the hook. Use `git rev-parse --git-dir` instead of `[ -d .git ]`
# so the unwire works in worktrees and submodules, where `.git` is a file.
if git rev-parse --git-dir >/dev/null 2>&1 \
   && [ "$(git config --get core.hooksPath || true)" = ".githooks" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "would unset:  core.hooksPath"
  else
    git config --unset core.hooksPath
    echo "unset:        core.hooksPath"
  fi
fi

echo ""
[ "$DRY_RUN" -eq 1 ] && echo "Dry run — no files changed." || echo "Done."
