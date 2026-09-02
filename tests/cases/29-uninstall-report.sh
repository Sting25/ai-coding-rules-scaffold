# shellcheck shell=bash
# cases/29-uninstall-report.sh, what uninstall.sh REPORTS and what it touches.
# Sourced into the driver's shell, so PASS/FAIL/HOOK_OUT/SCAFFOLD_DIR are in
# scope. A separate file from cases/09 because that one already sits exactly on
# the scaffold's own 500-line cap.
#
# Two questions, both of which uninstall.sh answered wrongly:
#   1. does --dry-run actually change nothing? (it deleted directories)
#   2. does a real run name the files it deliberately leaves behind? (it did not)
# Every assertion below is positive: the tree is provably unchanged AND the
# wanted lines are provably printed. "No error appeared" is never the test.

echo ""
echo "uninstall.sh reporting (dry run, leftovers):"

# un_project, a fresh frontend install in a throwaway repo. --frontend keeps the
# install fast and deterministic (no Python toolchain probing).
un_project() {
  local t
  t=$(mktemp -d)
  ( cd "$t" && git init --quiet && echo '{"name":"x"}' >package.json \
    && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >/dev/null 2>&1
  printf '%s' "$t"
}

# (A) --dry-run must not touch the filesystem. The empty-directory sweep at the
# end of uninstall.sh called rmdir with no DRY_RUN guard, unlike every other
# removal in the script, so a dry run genuinely deleted .claude/, .cursor/ and
# every other already-empty scaffold directory while its closing line said
# "no files changed". Both halves are asserted: the tree is identical afterwards
# AND the run still names what it would remove, because a dry run that prints
# nothing is equally "harmless" and equally useless.
UDRY=$(un_project)
UDRO=$(mktemp -d)
( cd "$UDRY" && mkdir -p .claude .cursor \
  && find . -path ./.git -prune -o -print | sort >"$UDRO/before.list" \
  && "$SCAFFOLD_DIR/uninstall.sh" --dry-run \
  && find . -path ./.git -prune -o -print | sort >"$UDRO/after.list" ) >"$HOOK_OUT" 2>&1
UDRY_HOOKS=$( cd "$UDRY" && git config --get core.hooksPath || true )
if diff -q "$UDRO/before.list" "$UDRO/after.list" >/dev/null 2>&1 \
   && [ -d "$UDRY/.claude" ] && [ -d "$UDRY/.cursor" ] \
   && [ -f "$UDRY/.githooks/pre-commit" ] \
   && [ "$UDRY_HOOKS" = ".githooks" ] \
   && grep -qF "would remove: .githooks/pre-commit" "$HOOK_OUT" \
   && grep -qF "would remove empty: .claude" "$HOOK_OUT" \
   && grep -qF "would remove empty: .cursor" "$HOOK_OUT"; then
  echo "  ✓ --dry-run deletes nothing and still names what it would remove"; PASS=$((PASS + 1))
else
  echo "  ✗ --dry-run changed the tree (or stopped naming removals)"
  diff "$UDRO/before.list" "$UDRO/after.list" | sed 's/^/      /' || true
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$UDRY" "$UDRO"

# (B) ...and the dry run must be TRUTHFUL, not merely inert: the directories it
# says it would clear are exactly the ones a real run does clear. Nothing is
# deleted during a dry run, so the sweep cannot ask the filesystem whether
# .githooks/lib is empty (it still holds every file); it has to replay the
# removals it just reported. A fix that only skipped rmdir would print an empty
# list here and still pass (A).
UDT=$(un_project)
UDTO=$(mktemp -d)
( cd "$UDT" && "$SCAFFOLD_DIR/uninstall.sh" --dry-run ) >"$UDTO/dry.txt" 2>&1
( cd "$UDT" && "$SCAFFOLD_DIR/uninstall.sh" ) >"$UDTO/real.txt" 2>&1
sed -n 's/^would remove empty: //p' "$UDTO/dry.txt"  | sort >"$UDTO/dry.dirs"
sed -n 's/^removed empty: //p'      "$UDTO/real.txt" | sort >"$UDTO/real.dirs"
if [ -s "$UDTO/dry.dirs" ] && grep -qx '.githooks/lib' "$UDTO/dry.dirs" \
   && diff -q "$UDTO/dry.dirs" "$UDTO/real.dirs" >/dev/null 2>&1; then
  echo "  ✓ --dry-run reports the same empty dirs a real run removes"; PASS=$((PASS + 1))
else
  echo "  ✗ dry-run empty-dir report does not match the real run"
  diff "$UDTO/dry.dirs" "$UDTO/real.dirs" | sed 's/^/      /' || true
  FAIL=$((FAIL + 1))
fi
rm -rf "$UDT" "$UDTO"

# (C) --help printed its usage header through a hardcoded sed line range that
# was one line short, so the last line of the header, the --help flag itself,
# never appeared. The header is now printed by its shape (comment lines after
# the shebang, stopping at the first non-comment line), so it cannot drift
# again. Asserted from both ends: every flag is listed, and the print still
# stops at the header instead of spilling code into the usage text.
UHLP=$(mktemp -d)
( "$SCAFFOLD_DIR/uninstall.sh" --help ) >"$UHLP/help.txt" 2>&1
if grep -qF -- "uninstall.sh --help" "$UHLP/help.txt" \
   && grep -qF -- "uninstall.sh --all" "$UHLP/help.txt" \
   && grep -qF -- "uninstall.sh --dry-run" "$UHLP/help.txt" \
   && ! grep -qF "set -euo pipefail" "$UHLP/help.txt"; then
  echo "  ✓ --help lists every flag it accepts, including --help"; PASS=$((PASS + 1))
else
  echo "  ✗ --help output is truncated or overruns the header"
  sed 's/^/      /' "$UHLP/help.txt"; FAIL=$((FAIL + 1))
fi
rm -rf "$UHLP"

# (D) A safe-mode uninstall deliberately keeps the likely-customized files
# (AGENTS.md, coding-rules.md, operational-rules.md, .forbidden-patterns/) and
# used to say nothing at all about them: the policy lived only in the script
# header, so the run ended with "Done." over a project that still had six
# scaffold files in it and no way to know. Assert every kept path is named, and
# that the line names the flag that finishes the job.
ULFT=$(un_project)
( cd "$ULFT" && "$SCAFFOLD_DIR/uninstall.sh" ) >"$HOOK_OUT" 2>&1
if grep -qF "kept (likely customized):" "$HOOK_OUT" \
   && grep -qF "AGENTS.md" "$HOOK_OUT" \
   && grep -qF "coding-rules.md" "$HOOK_OUT" \
   && grep -qF "operational-rules.md" "$HOOK_OUT" \
   && grep -qF ".forbidden-patterns/" "$HOOK_OUT" \
   && grep -qF "uninstall.sh --all" "$HOOK_OUT" \
   && [ -f "$ULFT/AGENTS.md" ] && [ -d "$ULFT/.forbidden-patterns" ]; then
  echo "  ✓ a safe uninstall names every file it leaves behind"; PASS=$((PASS + 1))
else
  echo "  ✗ uninstall left files behind without naming them"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$ULFT"

# (E) An upgrade's .scaffold-bak copies are the user's ONLY copy of their own
# edits, so uninstall must not delete them. It must still say they are there:
# they are scaffold-created files with a scaffold-shaped name, and a user who
# does not know they exist never merges anything back out of them.
UBAK=$(un_project)
( cd "$UBAK" && printf '# local edit\n' >>.githooks/pre-commit \
  && "$SCAFFOLD_DIR/install.sh" --frontend --force --no-verify ) >/dev/null 2>&1
( cd "$UBAK" && "$SCAFFOLD_DIR/uninstall.sh" ) >"$HOOK_OUT" 2>&1
if [ -f "$UBAK/.githooks/pre-commit.scaffold-bak" ] \
   && grep -qF "local edit" "$UBAK/.githooks/pre-commit.scaffold-bak" \
   && grep -qF "kept (your backups):" "$HOOK_OUT" \
   && grep -qF ".githooks/pre-commit.scaffold-bak" "$HOOK_OUT"; then
  echo "  ✓ uninstall keeps .scaffold-bak copies and names them"; PASS=$((PASS + 1))
else
  echo "  ✗ .scaffold-bak backups were deleted or went unreported"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$UBAK"

# (F) --all really does remove the kept set, so the closing line is not advice
# that goes nowhere. The kept block must NOT claim a file is still there when
# the run just deleted it.
UALL=$(un_project)
( cd "$UALL" && "$SCAFFOLD_DIR/uninstall.sh" --all ) >"$HOOK_OUT" 2>&1
if [ ! -e "$UALL/AGENTS.md" ] && [ ! -e "$UALL/coding-rules.md" ] \
   && [ ! -e "$UALL/.forbidden-patterns" ] \
   && ! grep -qF "kept (likely customized):" "$HOOK_OUT"; then
  echo "  ✓ --all removes the kept set and drops the kept notice"; PASS=$((PASS + 1))
else
  echo "  ✗ --all left the customized files or still called them kept"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$UALL"

reset_repo
