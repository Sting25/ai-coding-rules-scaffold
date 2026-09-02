# shellcheck shell=bash
# cases/12-install-backup-cap.sh — install.sh's _backup >99-cap must not abort the
# whole run (audit B12). Sourced into the driver's shell, so the globals
# (PASS/FAIL/HOOK_OUT/SCAFFOLD_DIR) and helpers (reset_repo) are already in scope.
# Split out of cases/09 (which is at the 500-line module cap) rather than weakened.

echo "cases/12 — install backup-cap skip (B12)"

# With all 100 .scaffold-bak[.N] slots taken for one --force'd file, _backup used
# to `return 1`; the bare cp_safe call then aborted the entire script under set -e,
# leaving hooks unwired with no summary. It now SKIPS that one file — leaving the
# user's version untouched (no backup ⇒ no safe overwrite) — and finishes the rest.
B12=$(mktemp -d)
( cd "$B12" && git init --quiet && echo '{"name":"x"}' >package.json && echo 'name="x"' >pyproject.toml \
  && "$SCAFFOLD_DIR/install.sh" --both --no-verify >/dev/null 2>&1 )
# Make ruff.toml (a user-owned cp_safe file) differ so --force will try to back it up.
echo '# LOCAL EDIT B12' >>"$B12/ruff.toml"
# Saturate the backup slots: base + .1..99 = 100 existing ⇒ the cap trips.
: >"$B12/ruff.toml.scaffold-bak"
for i in $(seq 1 99); do : >"$B12/ruff.toml.scaffold-bak.$i"; done
if ( cd "$B12" && "$SCAFFOLD_DIR/install.sh" --both --force --no-verify ) >"$HOOK_OUT" 2>&1 \
   && grep -q 'too many .scaffold-bak' "$HOOK_OUT" \
   && grep -q 'Done' "$HOOK_OUT" \
   && grep -q 'LOCAL EDIT B12' "$B12/ruff.toml"; then
  echo "  ✓ install skips an over-backup-capped file and completes (no mid-run abort) (B12)"; PASS=$((PASS + 1))
else
  echo "  ✗ install aborted on the backup cap or clobbered the capped file (B12)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$B12"
reset_repo

# (T) _backup's COPY is load-bearing (audit shell-03-backup-silent-failure).
# _backup used to run `cp -P` unchecked, then print "backed up:" and return 0
# regardless. Every caller invokes it with errexit disabled, so a failed copy
# was swallowed and the caller went on to OVERWRITE the user's file with no
# backup anywhere: measured as a local edit destroyed, no .scaffold-bak on
# disk, and install.sh still exiting 0 with a "backed up:" line in the log.
# The copy now decides: if it fails, that ONE file is skipped (left untouched)
# and the failure is named, same policy as the >99-slot cap above.
#
# Making cp fail without depending on who is running: a mode-000 file is the
# audit's own repro and works for any normal user, but root ignores mode bits,
# so as root the destination becomes a DIRECTORY instead, which `cp -P` also
# refuses to copy. Either way the copy fails for a real reason.
SBF=$(mktemp -d)
( cd "$SBF" && git init --quiet && echo '{"name":"x"}' >package.json \
  && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify >/dev/null 2>&1 )
if [ "$(id -u)" -eq 0 ]; then
  rm -f "$SBF/.githooks/lib/check-size"
  mkdir -p "$SBF/.githooks/lib/check-size/keep"
  printf 'PRECIOUS LOCAL EDIT\n' >"$SBF/.githooks/lib/check-size/keep/marker"
else
  printf '\n# PRECIOUS LOCAL EDIT\n' >>"$SBF/.githooks/lib/check-size"
  chmod 000 "$SBF/.githooks/lib/check-size"
fi
SBF_RC=0
( cd "$SBF" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1 || SBF_RC=$?
chmod -R u+rwX "$SBF" 2>/dev/null || true
if [ "$SBF_RC" -eq 0 ] \
   && grep -q 'error: could not back up .githooks/lib/check-size' "$HOOK_OUT" \
   && ! grep -q 'backed up:    .githooks/lib/check-size' "$HOOK_OUT" \
   && grep -q 'Done' "$HOOK_OUT" \
   && grep -qr 'PRECIOUS LOCAL EDIT' "$SBF/.githooks/lib/check-size" \
   && [ ! -e "$SBF/.githooks/lib/check-size.scaffold-bak" ]; then
  echo "  ✓ a failed backup copy is reported and the file is left untouched (shell-03)"; PASS=$((PASS + 1))
else
  echo "  ✗ a failed backup copy should be named and skip that file, never overwrite it (shell-03)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$SBF"
reset_repo

# (T) an upgrade's leftover backups are neither executable nor committable
# (audit upgrade-path-2). _backup writes <file>.scaffold-bak as a SIBLING of the
# file it replaces, so .githooks/pre-commit produced
# .githooks/pre-commit.scaffold-bak at mode 100755, untracked and un-ignored:
# measured, a plain `git add -A && git commit` in an upgraded project committed
# two of them into .githooks/ ("create mode 100755"), and 6 accumulated after a
# v0.8.0 -> HEAD upgrade. Nothing in install.sh, uninstall.sh or the doctor had
# ever mentioned them. Now they arrive non-executable and .gitignore carries the
# two rules that keep them out of a commit.
BAKH=$(mktemp -d)
( cd "$BAKH" && git init --quiet && echo '{"name":"x"}' >package.json \
  && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify >/dev/null 2>&1 \
  && git add -A && git commit --quiet -m "base" --no-verify )  # scaffold-allow: test fixture
# Force a real backup on a scaffold-owned, executable file: edit it so the
# re-run's refresh has something to back up.
printf '\n# local edit that forces a backup\n' >>"$BAKH/.githooks/pre-commit"
( cd "$BAKH" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1
BAKH_STAGED=""
if [ -f "$BAKH/.githooks/pre-commit.scaffold-bak" ]; then
  BAKH_STAGED=$( cd "$BAKH" || exit 0
                 git add -A >/dev/null 2>&1
                 git diff --cached --name-only | grep scaffold-bak || true )
fi
if [ -f "$BAKH/.githooks/pre-commit.scaffold-bak" ] \
   && [ ! -x "$BAKH/.githooks/pre-commit.scaffold-bak" ] \
   && grep -q '^\*\.scaffold-bak$' "$BAKH/.gitignore" \
   && grep -q '^\*\.scaffold-bak\.\*$' "$BAKH/.gitignore" \
   && ( cd "$BAKH" && git check-ignore -q .githooks/pre-commit.scaffold-bak ) \
   && [ -z "$BAKH_STAGED" ]; then
  echo "  ✓ an install backup is non-executable and gitignored, so git add -A cannot commit it"; PASS=$((PASS + 1))
else
  echo "  ✗ an install backup should be non-executable and gitignored (upgrade-path-2)"
  echo "      staged: ${BAKH_STAGED:-none}"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$BAKH"

# (T) .gitignore is the project's file, not the scaffold's: the rules are
# appended once (a re-run does not duplicate them) and existing content is kept.
BAKG=$(mktemp -d)
printf 'node_modules/\n' >"$BAKG/.gitignore"
( cd "$BAKG" && git init --quiet && echo '{"name":"x"}' >package.json \
  && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify \
  && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1
if grep -q '^node_modules/$' "$BAKG/.gitignore" \
   && [ "$(grep -c '^\*\.scaffold-bak$' "$BAKG/.gitignore")" -eq 1 ]; then
  echo "  ✓ the .scaffold-bak ignore rules are appended once and keep existing .gitignore content"; PASS=$((PASS + 1))
else
  echo "  ✗ the .scaffold-bak ignore rules should be appended exactly once, keeping user content"
  sed 's/^/      /' "$BAKG/.gitignore"; FAIL=$((FAIL + 1))
fi
rm -rf "$BAKG"
reset_repo
