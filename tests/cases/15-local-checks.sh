# shellcheck shell=bash
# cases/15-local-checks.sh — the .githooks/local.d/ project-local check
# extension point, and cp_scaffold's unconditional backup (issue #72). Sourced
# into the driver's shell, so the globals (PASS/FAIL/HOOK_OUT/SCAFFOLD_DIR) and
# helpers are already in scope. Its own file: cases/09 is near the 500-line cap.
#
# What #72 was: .githooks/pre-commit and .github/workflows/lint.yml were the only
# places a project could wire in a local check, both were cp_scaffold at the time
# (refreshed on a plain re-run; lint.yml has since moved to cp_scaffold_preserve,
# #105), and cp_scaffold took no backup without --force. So an upgrade
# reset the call site with no backup and no signal — the check script stayed on
# disk, nothing errored, and the guardrail became decoration.

echo "cases/15 — project-local checks + upgrade backup (#72)"

# A local check with the documented contract: NUL-delimited list on stdin, scans
# the committed blob, non-zero exit blocks. Written to $1/.githooks/local.d.
_plant_local_check() {
  cat >"$1/.githooks/local.d/20-banned" <<'LC_EOF'
#!/usr/bin/env bash
set -euo pipefail
FAILED=0
while IFS= read -r -d '' f; do
  case "$f" in *.py) ;; *) continue ;; esac
  if git show ":0:$f" 2>/dev/null | grep -q 'ZZBANNEDZZ'; then
    echo "local check: ZZBANNEDZZ in $f"; FAILED=1
  fi
done
exit $FAILED
LC_EOF
  chmod +x "$1/.githooks/local.d/20-banned"
}

# A fixture project with the scaffold installed. `core.hooksPath` is pointed at
# a nonexistent dir for the SEED commit rather than passing --no-verify: shell.txt
# forbids that flag and this harness is a .sh file the scaffold scans itself.
#
# --shell, deliberately. These assertions are about whether local.d ran, so the
# hook's OPTIONAL linter steps must not be able to fail the commit for unrelated
# reasons and be misread as a verdict on local.d. A `package.json` fixture is a
# frontend install, which lands tsconfig.json and makes the hook run
# `tsc --noEmit` wherever npx resolves a tsc — green on a runner without one and
# red on a runner with one, on `Cannot find module 'vitest/config'` in a fixture
# that never ran npm install. Shell mode installs no ruff/eslint/prettier/tsc
# config, so nothing but the guardrails and local.d can decide the exit status.
_fixture() {
  local d; d=$(mktemp -d)
  ( cd "$d" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" && git config core.hooksPath .nohooks \
    && printf '#!/usr/bin/env bash\necho seed\n' >seed.sh && git add -A \
    && git -c user.email=t@t -c user.name=t commit --quiet -m seed \
    && "$SCAFFOLD_DIR/install.sh" --shell ) >/dev/null 2>&1
  ( cd "$d" && git config --unset core.hooksPath && git config core.hooksPath .githooks )
  printf '%s' "$d"
}

# (T) install.sh creates local.d with an INERT README — inert because the hook's
#     -x guard skips it. A README that arrived executable would be RUN.
LTMP=$(_fixture)
if [ -f "$LTMP/.githooks/local.d/README.md" ] && [ ! -x "$LTMP/.githooks/local.d/README.md" ]; then
  echo "  ✓ install.sh creates .githooks/local.d/ with a non-executable README"; PASS=$((PASS + 1))
else
  echo "  ✗ local.d README missing or executable (an executable README would be run as a check)"; FAIL=$((FAIL + 1))
fi

# (T) A local check BLOCKS a commit. The whole point — without this the
#     extension point is decoration, which is the bug being fixed.
_plant_local_check "$LTMP"
printf 'x = 1  # ZZBANNEDZZ\n' >"$LTMP/bad.py"
LRC=0
( cd "$LTMP" && git add -A \
  && git -c user.email=t@t -c user.name=t commit --quiet -m "blocked" ) >"$HOOK_OUT" 2>&1 || LRC=$?
if [ "$LRC" -ne 0 ] && grep -qF "local check: ZZBANNEDZZ in bad.py" "$HOOK_OUT"; then
  echo "  ✓ an executable in local.d/ blocks the commit"; PASS=$((PASS + 1))
else
  echo "  ✗ local.d check did not block the commit (rc=$LRC)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi

# (T) MUTATION, the other direction: the executable bit is the on/off switch.
#     chmod -x must disable the check without deleting it — the disable path the
#     shipped README documents. Guards against a future blanket `chmod +x` in
#     the hook or the CI job silently re-arming a check the user turned off.
chmod -x "$LTMP/.githooks/local.d/20-banned"
LRC2=0
( cd "$LTMP" && git add -A \
  && git -c user.email=t@t -c user.name=t commit --quiet -m "passes" ) >"$HOOK_OUT" 2>&1 || LRC2=$?
if [ "$LRC2" -eq 0 ]; then
  echo "  ✓ chmod -x disables a local check (executable bit is the switch)"; PASS=$((PASS + 1))
else
  echo "  ✗ a non-executable file in local.d/ still ran (rc=$LRC2)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
chmod +x "$LTMP/.githooks/local.d/20-banned"

# (T) THE ISSUE ITSELF: a plain re-run (the documented upgrade path, no --force)
#     must not destroy a locally-edited scaffold-owned file without a trace. The
#     refresh still happens — cp_scaffold delivers security fixes — but the prior
#     bytes land in .scaffold-bak and a "backed up:" line makes it visible.
printf '\n# project-local wiring\necho local-marker-ZZ\n' >>"$LTMP/.githooks/pre-commit"
( cd "$LTMP" && "$SCAFFOLD_DIR/install.sh" ) >"$HOOK_OUT" 2>&1 || true
if [ -f "$LTMP/.githooks/pre-commit.scaffold-bak" ] \
   && grep -qF "local-marker-ZZ" "$LTMP/.githooks/pre-commit.scaffold-bak" \
   && grep -qF "backed up:" "$HOOK_OUT"; then
  echo "  ✓ a plain re-run backs up an edited scaffold-owned file and says so"; PASS=$((PASS + 1))
else
  echo "  ✗ edited .githooks/pre-commit was overwritten with no backup (#72)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi

# (T) ...and the refresh still lands, so the backup did not cost the upgrade its
#     security fixes. The local edit is gone from the live file (expected — it is
#     scaffold-owned); recoverable is the guarantee, not preserved.
if ! grep -qF "local-marker-ZZ" "$LTMP/.githooks/pre-commit" \
   && cmp -s "$SCAFFOLD_DIR/githooks/pre-commit.template" "$LTMP/.githooks/pre-commit"; then
  echo "  ✓ the refresh still delivers the shipped hook (backup is not a skip)"; PASS=$((PASS + 1))
else
  echo "  ✗ backing up suppressed the cp_scaffold refresh — upgraders would miss fixes"; FAIL=$((FAIL + 1))
fi

# (T) local.d is NEVER written by the upgrade. This is what makes it a safe home
#     for a local check, unlike the call site clobbered two assertions above.
if [ -x "$LTMP/.githooks/local.d/20-banned" ] \
   && grep -qF "ZZBANNEDZZ" "$LTMP/.githooks/local.d/20-banned" \
   && [ ! -e "$LTMP/.githooks/local.d/20-banned.scaffold-bak" ]; then
  echo "  ✓ a re-run leaves local.d/ entirely alone"; PASS=$((PASS + 1))
else
  echo "  ✗ install.sh touched .githooks/local.d/ — the extension point is not upgrade-safe"; FAIL=$((FAIL + 1))
fi

# (T) The CI half. Reproduce lint.yml's guardrails loop verbatim: --ci, the
#     NUL-delimited list on stdin, exit status propagated, README skipped. The
#     hook and CI must agree or a check passes locally and vanishes server-side.
CI_RAN=""
CI_FAILED=0
CI_LIST=$(mktemp)
( cd "$LTMP" && git -c core.quotepath=off ls-files -z ) >"$CI_LIST"
for lc in "$LTMP"/.githooks/local.d/*; do
  if [ ! -f "$lc" ] || [ ! -x "$lc" ]; then
    continue
  fi
  CI_RAN="$CI_RAN $(basename "$lc")"
  ( cd "$LTMP" && "$lc" --ci ) <"$CI_LIST" >/dev/null 2>&1 || CI_FAILED=1
done
rm -f "$CI_LIST"
if [ "$CI_FAILED" -eq 1 ] && [ "$CI_RAN" = " 20-banned" ]; then
  echo "  ✓ the CI guardrails loop runs local.d/ with --ci and skips the README"; PASS=$((PASS + 1))
else
  echo "  ✗ CI loop mismatch (failed=$CI_FAILED ran=$CI_RAN) — hook and CI disagree"; FAIL=$((FAIL + 1))
fi

rm -rf "$LTMP"
reset_repo
