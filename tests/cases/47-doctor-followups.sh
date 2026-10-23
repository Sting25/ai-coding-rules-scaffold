# shellcheck shell=bash
# cases/47-doctor-followups.sh: scaffold-doctor follow-ups from issues #187 and
# #193. Sourced into the driver's shell, so PASS/FAIL/HOOK_OUT/SCAFFOLD_DIR are
# in scope. Builds its own fixture (helpers prefixed docf_) so it does not
# depend on an earlier case file's helpers.

echo "cases/47: scaffold-doctor follow-ups (#193 local.d backups, #187 self-host and heading drift)"

docf_project() {
  local __docf_var=$1 t
  fixture_repo t
  echo '#!/usr/bin/env bash' >"$t/run.sh"
  fixture_install "$t" --shell --no-verify
  printf -v "$__docf_var" '%s' "$t"
}

# (A) #193: the installer leaves local.d/README.md.scaffold-bak beside a
# refreshed README.md. It is not a check, so it must not be reported at all;
# a real non-executable check next to it still is (the off-switch note).
docf_project DOCF
mkdir -p "$DOCF/.githooks/local.d"
printf 'old\n' >"$DOCF/.githooks/local.d/README.md.scaffold-bak"
printf '#!/bin/sh\nexit 0\n' >"$DOCF/.githooks/local.d/mine.sh"
chmod -x "$DOCF/.githooks/local.d/mine.sh"
docf_rc=0
( cd "$DOCF" && "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || docf_rc=$?
if [ "$docf_rc" -eq 0 ] && ! grep -qF "scaffold-bak" "$HOOK_OUT" \
   && grep -qF "local.d/mine.sh present but not executable" "$HOOK_OUT"; then
  echo "  ✓ a local.d/*.scaffold-bak backup is ignored; a real non-executable check is still noted"
  PASS=$((PASS + 1))
else
  echo "  ✗ local.d backup handling wrong (exit $docf_rc)"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$DOCF"

# (B) #187: section 9 lives in scaffold-doctor-drift.sh. A doctor copied
# without it must say so in a note and still exit 0 on a healthy project.
DRIFTMOD=$(mktemp -d)
cp "$SCAFFOLD_DIR/scaffold-doctor.sh" "$DRIFTMOD/scaffold-doctor.sh"
docf_project DOCF
docf_rc=0
( cd "$DOCF" && "$DRIFTMOD/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || docf_rc=$?
if [ "$docf_rc" -eq 0 ] \
   && grep -qF "scaffold-doctor-drift.sh not found next to scaffold-doctor.sh ($DRIFTMOD)" "$HOOK_OUT" \
   && ! grep -qF "carries every section of the shipped template" "$HOOK_OUT"; then
  echo "  ✓ a doctor copied without scaffold-doctor-drift.sh reports a note, not a crash or a false ok"
  PASS=$((PASS + 1))
else
  echo "  ✗ the missing-drift-module fallback misbehaved (exit $docf_rc)"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$DOCF" "$DRIFTMOD"

# (C) #187: the scaffold checkout holds the shipped coding-rules.md and no root
# CLAUDE.md, so the #136 import check has nothing to report there. Run the
# doctor from a copy of that shape (the doctor beside its own project root) and
# from an ordinary install with CLAUDE.md removed: the first is a note, the
# second must stay a gap, or the skip has widened into "never check".
SELFH=$(mktemp -d)
cp "$SCAFFOLD_DIR/scaffold-doctor.sh" "$SCAFFOLD_DIR/scaffold-doctor-drift.sh" "$SCAFFOLD_DIR/coding-rules.md" "$SELFH/"
git -C "$SELFH" init -q
docf_rc=0
( cd "$SELFH" && bash ./scaffold-doctor.sh ) >"$HOOK_OUT" 2>&1 || docf_rc=$?
if grep -qF "CLAUDE.md import check skipped" "$HOOK_OUT" \
   && ! grep -qF "there is no CLAUDE.md to import it" "$HOOK_OUT"; then
  echo "  ✓ the #136 import check is skipped when the project is the scaffold checkout"
  PASS=$((PASS + 1))
else
  echo "  ✗ the self-host skip did not apply (exit $docf_rc)"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$SELFH"
docf_project DOCF
rm -f "$DOCF/CLAUDE.md"
docf_rc=0
( cd "$DOCF" && "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || docf_rc=$?
if [ "$docf_rc" -eq 1 ] && grep -qF "coding-rules.md exists but there is no CLAUDE.md to import it" "$HOOK_OUT" \
   && ! grep -qF "import check skipped" "$HOOK_OUT"; then
  echo "  ✓ an installed project with no CLAUDE.md is still a gap"
  PASS=$((PASS + 1))
else
  echo "  ✗ the missing-CLAUDE.md gap was lost (exit $docf_rc)"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$DOCF"

unset DOCF DRIFTMOD SELFH docf_rc
unset -f docf_project
reset_repo
