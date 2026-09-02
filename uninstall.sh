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
    # Print the header by its SHAPE, not by line number: every comment line
    # after the shebang, stopping at the first line that is not one. The old
    # hardcoded `sed -n '2,15p'` was one line short of the header, so the only
    # flag it never listed was --help itself, and any edit to the header would
    # have silently moved the truncation point again.
    --help|-h) awk 'NR > 1 && /^#/ { print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    *) echo "error: unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# A dry run must not touch the filesystem. The empty-directory sweep at the end
# of this script cannot ask the filesystem whether a directory is empty during a
# dry run, because nothing has been deleted yet: .githooks/lib still holds every
# file a real run would have removed by then. WOULD_REMOVE records each path a
# real run would delete and the sweep replays the same order against that list,
# so a dry run names exactly the directories a real run clears without touching
# one of them. Before this existed the sweep called rmdir unguarded, so
# `uninstall.sh --dry-run` genuinely deleted directories while its last line
# said "no files changed".
NL='
'
WOULD_REMOVE=""
mark_removed() { WOULD_REMOVE="${WOULD_REMOVE}${1}${NL}"; }
is_marked() {
  case "${NL}${WOULD_REMOVE}" in
    *"${NL}${1}${NL}"*) return 0 ;;
  esac
  return 1
}

# dir_would_be_empty DIR: true when every entry in DIR is a path a real run
# would already have removed (or DIR has no entries at all). Hidden entries are
# globbed explicitly: an unmatched glob stays literal, which the -e/-L test then
# skips.
dir_would_be_empty() {
  local dir=$1 entry
  for entry in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
    { [ -e "$entry" ] || [ -L "$entry" ]; } || continue
    is_marked "$entry" || return 1
  done
  return 0
}

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
      mark_removed "$installed"
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
  # `|| return` (no status) returned the FAILED test's 1, and this script runs
  # under errexit with force_remove called at top level, so a single absent path
  # aborted the whole uninstall mid-sweep: no empty-dir pass, no hooksPath
  # unwire, no leftovers report, exit 1 and not one word about why. Reachable
  # today (--all with AGENTS.md already deleted), and reachable on every
  # pre-manifest install once the manifest below is removed unconditionally.
  # A path that is not there is nothing to do, which is success.
  { [ -e "$path" ] || [ -L "$path" ]; } || return 0
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "would remove: $path"
    mark_removed "$path"
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
      mark_removed "CLAUDE.md"
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

# backups_remain: true when any *.scaffold-bak file the installer could have
# left is still on disk. Used to decide whether the ignore rules that cover
# them may be removed.
backups_remain() {
  local f
  for f in ./*.scaffold-bak* .githooks/*.scaffold-bak* .githooks/lib/*.scaffold-bak* \
           .github/workflows/*.scaffold-bak* .forbidden-patterns/*.scaffold-bak* \
           .claude/*.scaffold-bak* .cursor/*.scaffold-bak*; do
    [ -e "$f" ] && return 0
  done
  return 1
}

# clean_gitignore: install.sh appends a marked block of ignore rules for the
# artifacts it can leave behind (*.scaffold-bak, the manifest scratch files).
# Nothing here ever removed it or even named it, so an uninstalled project kept
# scaffold rules in a file nobody thinks to check. .gitignore is the project's
# file, so this strips ONLY our block, bounded by the end marker exactly as
# clean_claude_md is (an open-ended delete to EOF would eat the project's own
# rules below it). If that leaves nothing but blank lines, the file was ours to
# begin with (install.sh creates .gitignore when a project has none), so it goes
# too. A block appended before it carried markers cannot be bounded safely, so
# it is named rather than guessed at.
#
# _gitignore_has_unmarked_rules: a scaffold ignore rule sitting OUTSIDE the
# marked block, which is what an install from before the markers left (and what
# stripping the block leaves behind). Checked outside the block specifically, so
# it reports the same thing before a strip, after one, and in a dry run.
_gitignore_has_unmarked_rules() {
  awk '
    $0 == "# ai-coding-rules-scaffold:begin" { inblock = 1; next }
    $0 == "# ai-coding-rules-scaffold:end"   { inblock = 0; next }
    !inblock && $0 ~ /^[[:space:]]*\*\.scaffold-bak/ { found = 1 }
    END { exit(found ? 0 : 1) }
  ' ".gitignore" 2>/dev/null
}

clean_gitignore() {
  local has_begin=0 has_end=0
  [ -e ".gitignore" ] || return 0
  # Safe mode keeps every *.scaffold-bak file, and says so, because those are
  # the only copy of the edits they replaced. Stripping the rules that ignore
  # them in the same run would leave them untracked and unignored, so the next
  # `git add -A` commits them. That is the defect this scaffold fixes for its
  # own scratch files, so do not recreate it here: while a backup survives, the
  # rules protecting it survive too.
  if [ "$REMOVE_ALL" -eq 0 ] && backups_remain; then
    echo "kept:         scaffold ignore rules in .gitignore (they cover the *.scaffold-bak files kept above)"
    return 0
  fi
  if [ -L ".gitignore" ]; then
    echo "kept:         .gitignore is a symlink, left untouched (remove any '*.scaffold-bak' rules by hand)"
    return 0
  fi
  if grep -q '^# ai-coding-rules-scaffold:begin$' ".gitignore" 2>/dev/null; then has_begin=1; fi
  if grep -q '^# ai-coding-rules-scaffold:end$'   ".gitignore" 2>/dev/null; then has_end=1; fi
  if [ "$has_begin" -eq 1 ] && [ "$has_end" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
    # Same awk shape as clean_claude_md: drop begin..end plus the blank spacer
    # install.sh put in front of it, via a temp file so a failure cannot
    # truncate the original.
    if awk '
      $0 == "" && !inblock { if (pend) print hold; hold = $0; pend = 1; next }
      $0 == "# ai-coding-rules-scaffold:begin" { inblock = 1; pend = 0; next }
      $0 == "# ai-coding-rules-scaffold:end"   { inblock = 0; next }
      { if (inblock) next; if (pend) { print hold; pend = 0 } print }
      END { if (pend) print hold }
    ' ".gitignore" >".gitignore.scaffold-tmp"; then
      mv ".gitignore.scaffold-tmp" ".gitignore"
      echo "stripped:     scaffold ignore rules from .gitignore (your rules kept)"
    else
      rm -f ".gitignore.scaffold-tmp"
      echo "error:        failed to rewrite .gitignore, left untouched" >&2
      return 0
    fi
    if [ -z "$(tr -d '[:space:]' <".gitignore")" ]; then
      rm -f ".gitignore"
      echo "removed:      .gitignore (scaffold-created, nothing of yours left in it)"
      return 0
    fi
  elif [ "$has_begin" -eq 1 ] && [ "$has_end" -eq 1 ]; then
    echo "would strip:  scaffold ignore rules from .gitignore (your rules kept)"
  fi
  # Whatever is left: an unmarked block is named, never guessed at, so it is not
  # a leftover nobody can see.
  if _gitignore_has_unmarked_rules; then
    echo "kept:         .gitignore holds scaffold ignore rules (*.scaffold-bak) from an install that predates the marked block; unmarked lines are not ours to bound, so delete them by hand"
  fi
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
for check in check-size check-large-files check-patterns check-filenames check-secrets check-hygiene scaffold-config scaffold-audit ci-changed-files; do
  remove_if_unmodified ".githooks/lib/${check}" "$SCAFFOLD_DIR/githooks/lib/${check}.template"
done
# Per-project override file — removed only if still byte-identical to the
# shipped (empty) template; a team that has recorded overrides keeps it.
remove_if_unmodified ".scaffold.toml"                "$SCAFFOLD_DIR/.scaffold.toml.template"
remove_if_unmodified ".github/workflows/lint.yml"    "$SCAFFOLD_DIR/.github/workflows/lint.yml.template"
# Default-on test-execution workflow (only present unless installed with
# --no-test-workflow, or superseded by --coverage-gate's coverage.yml below).
remove_if_unmodified ".github/workflows/tests.yml"   "$SCAFFOLD_DIR/.github/workflows/tests.yml.template"
# The local.d README only — never the directory. Anything else in there is a
# project's own check scripts, which the scaffold neither wrote nor owns; the
# rmdir sweep below clears the directory iff it is empty. Not touched by --all
# either: --all removes files the SCAFFOLD authored and a user then customized,
# and a local check is not one of those.
remove_if_unmodified ".githooks/local.d/README.md"   "$SCAFFOLD_DIR/githooks/local.d/README.md.template"
remove_if_unmodified ".github/dependabot.yml"        "$SCAFFOLD_DIR/.github/dependabot.yml.template"
clean_claude_md
# Opt-in Claude Code guardrails (only present if installed with --claude).
remove_if_unmodified ".githooks/lib/agent-precheck"  "$SCAFFOLD_DIR/githooks/lib/agent-precheck.template"
remove_if_unmodified ".claude/settings.json"         "$SCAFFOLD_DIR/claude-settings.json.template"
# Opt-in Cursor guardrails (only present if installed with --cursor).
remove_if_unmodified ".cursor/hooks.json"            "$SCAFFOLD_DIR/cursor-hooks.json.template"
remove_if_unmodified ".githooks/lib/credential-read-patterns.txt" "$SCAFFOLD_DIR/githooks/lib/credential-read-patterns.txt.template"
# Opt-in commit-msg hook (only present if installed with --commit-msg).
remove_if_unmodified ".githooks/commit-msg"          "$SCAFFOLD_DIR/githooks/commit-msg.template"
# Opt-in local gitleaks pass (only present if installed with --gitleaks-hook).
remove_if_unmodified ".githooks/lib/check-gitleaks"  "$SCAFFOLD_DIR/githooks/lib/check-gitleaks.template"
# Opt-in CI patch-coverage gate (only present if installed with --coverage-gate;
# installed INSTEAD OF tests.yml above, so at most one of the two exists).
remove_if_unmodified ".github/workflows/coverage.yml" "$SCAFFOLD_DIR/.github/workflows/coverage.yml.template"
# Opt-in gitleaks CI workflow (only present if installed with --gitleaks-ci).
remove_if_unmodified ".github/workflows/gitleaks.yml" "$SCAFFOLD_DIR/.github/workflows/gitleaks.yml.template"
# Opt-in dependency-review CI gate (only present if installed with
# --dependency-review).
remove_if_unmodified ".github/workflows/dependency-review.yml" "$SCAFFOLD_DIR/.github/workflows/dependency-review.yml.template"
# Opt-in zizmor CI gate (only present if installed with --zizmor-ci).
remove_if_unmodified ".github/workflows/zizmor.yml" "$SCAFFOLD_DIR/.github/workflows/zizmor.yml.template"
# Opt-in Socket Firewall supply-chain CI gate (only present if installed
# with --socket-ci).
remove_if_unmodified ".github/workflows/socket-security.yml" "$SCAFFOLD_DIR/.github/workflows/socket-security.yml.template"
# Opt-in red-green test-integrity gate (only present if installed with
# --test-guard, #140). The section it appended to coding-rules.md stays:
# coding-rules.md is user-owned, same policy as every other user-owned edit.
remove_if_unmodified ".github/workflows/test-guard.yml" "$SCAFFOLD_DIR/.github/workflows/test-guard.yml.template"
remove_if_unmodified ".githooks/lib/check-red-green" "$SCAFFOLD_DIR/githooks/lib/check-red-green.template"
# Advisory diff-scoped mutation layer for test-guard (#145).
remove_if_unmodified ".githooks/lib/check-mutation-diff" "$SCAFFOLD_DIR/githooks/lib/check-mutation-diff.template"
# Opt-in npm install-layer cooldown (only present if installed with
# --npm-cooldown, #117).
remove_if_unmodified ".npmrc" "$SCAFFOLD_DIR/.npmrc.template"
# Opt-in Claude Code Skill (only present if installed with --claude-skill,
# #118 pt 2).
remove_if_unmodified ".claude/skills/coding-rules/SKILL.md" "$SCAFFOLD_DIR/claude-skill/coding-rules/SKILL.md.template"

# Likely-customized files — only with --all
if [ "$REMOVE_ALL" -eq 1 ]; then
  force_remove "AGENTS.md"
  force_remove "coding-rules.md"
  force_remove "operational-rules.md"
  force_remove ".forbidden-patterns"
fi

# The install manifest and the scratch files a manifest write can leave behind
# (install-manifest.sh). Scaffold bookkeeping, not project content: every line
# in it is a sha256 of a file this script has just removed, its own header says
# "do not edit", and there is no user content in it to protect, so it goes in
# BOTH modes. It was skipped entirely before, which made it the leftover that
# no run named, no run removed, and that kept .githooks from ever being swept
# as empty even after a --all (the same defect as upgrade-path-4, reintroduced
# by the file that fixed it).
force_remove ".githooks/.scaffold-manifest"
for stale in .githooks/.scaffold-manifest.new.* .githooks/.scaffold-manifest.tmp.*; do
  if [ -e "$stale" ] || [ -L "$stale" ]; then
    force_remove "$stale"
  fi
done

clean_gitignore

# Clean up empty dirs the installer created
# local.d before .githooks, so an emptied local.d lets .githooks go too.
for dir in .githooks/lib .githooks/local.d .githooks .github/workflows .github \
           .claude/skills/coding-rules .claude/skills .claude .cursor; do
  [ -d "$dir" ] || continue
  if [ "$DRY_RUN" -eq 1 ]; then
    # Never rmdir here: a dry run reports, it does not delete.
    if dir_would_be_empty "$dir"; then
      echo "would remove empty: $dir"
      mark_removed "$dir"
    fi
  elif rmdir "$dir" 2>/dev/null; then
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

# --- what is deliberately left behind ---------------------------------------
# The safe path keeps the likely-customized files and every *.scaffold-bak an
# upgrade wrote, and it used to say nothing whatsoever about either: the policy
# lived only in this script's header, so a run ended with "Done." over a project
# that still had six scaffold files in it and no way to learn their names. A
# leftover nobody can name is a leftover nobody removes.
KEPT=""
if [ "$REMOVE_ALL" -eq 0 ]; then
  for kept_path in AGENTS.md coding-rules.md operational-rules.md; do
    if [ -e "$kept_path" ]; then
      KEPT="${KEPT}  ${kept_path}${NL}"
    fi
  done
  for kept_path in .forbidden-patterns/*.txt; do
    if [ -e "$kept_path" ]; then
      KEPT="${KEPT}  ${kept_path}${NL}"
    fi
  done
fi
if [ -n "$KEPT" ]; then
  echo ""
  echo "kept (likely customized): yours to edit, so uninstall never deletes them."
  printf '%s' "$KEPT"
  echo "  remove them too with: uninstall.sh --all"
fi

# The backups an upgrade or a --force install wrote hold the ONLY copy of the
# edits they replaced, so uninstall must never delete them. It must still name
# them: a user who does not know they exist never merges anything back out.
BAKS=$(find . -maxdepth 4 -name '*.scaffold-bak*' -not -path './.git/*' 2>/dev/null | sed 's|^\./||' | sort || true)
if [ -n "$BAKS" ]; then
  echo ""
  echo "kept (your backups): the only copy of the edits they replaced."
  printf '%s\n' "$BAKS" | sed 's/^/  /'
  echo "  merge anything you still want out of them, then delete them yourself."
fi

echo ""
[ "$DRY_RUN" -eq 1 ] && echo "Dry run — no files changed." || echo "Done."
