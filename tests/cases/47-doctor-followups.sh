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

unset DOCF docf_rc
unset -f docf_project
reset_repo
