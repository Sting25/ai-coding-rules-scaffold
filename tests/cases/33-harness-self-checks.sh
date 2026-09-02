# shellcheck shell=bash
# cases/29-harness-self-checks.sh: the scaffold's own harness and CI, checked
# by the suite they gate. Sourced into the driver's shell, so PASS/FAIL/
# HOOK_OUT/SCAFFOLD_DIR are in scope.
#
# Every other case file asks "did the scaffold reject the right thing". This one
# asks the question no other case can: "did the suite that answered actually
# run, and does its exit status say so". Two defects lived in tests/run.sh's
# last three lines:
#
#   1. No assertion floor. A case file that stops early (a stray `return`, a
#      guard that turns out false, a case dropped from the driver's list) takes
#      its assertions with it and the run still prints "0 failed". Measured:
#      prepending `return 0` to cases/07-agent-commit.sh drops 22 assertions and
#      reports "Result: 372 passed, 0 failed", exit 0, green CI.
#   2. `exit "$FAIL"` wrapped. An exit status is taken mod 256, so exactly 256
#      failing assertions exited 0 (and 394 would have exited 138). CI consumes
#      nothing but that status: .github/workflows/test.yml and release.yml both
#      just `run: ./tests/run.sh`, and release.yml's publish job `needs: test`.
#
# The assertions lift run.sh's REAL exit path out of the file and run it with a
# chosen PASS/FAIL, the same technique cases/16 uses on the coverage workflow.
# Asserting on the source text would pass against any rewrite that reintroduced
# the hole by another route; running it cannot. It also cannot recurse: only the
# tail after the case-sourcing loop is executed, so no nested suite runs.

echo "cases/29, the harness checks itself (tests/run.sh, shellcheck.yml)"

RUNSH="$SCAFFOLD_DIR/tests/run.sh"
HEP=$(mktemp -d)

# The floor must be a single greppable constant, or "bump it when you add a
# case" is not a followable instruction.
HEP_MIN=$(sed -n 's/^MIN_PASS=\([0-9][0-9]*\)$/\1/p' "$RUNSH")
if [ -n "$HEP_MIN" ]; then
  echo "  ✓ run.sh declares a single bumpable MIN_PASS constant (=$HEP_MIN)"
  PASS=$((PASS + 1))
else
  echo "  ✗ run.sh has no MIN_PASS=<n> line to bump when cases are added"
  FAIL=$((FAIL + 1))
fi

# Run run.sh's exit path (everything after the case-sourcing loop) with PASS and
# FAIL set to the values under test. Echoes the exit status; output lands in
# $HEP/out.
_hep_exit_path() {
  local p=$1 f=$2 rc=0
  {
    printf 'set -euo pipefail\nPASS=%s\nFAIL=%s\n' "$p" "$f"
    awk '/^# --- assertion floor/ { found = 1 } found { print }' "$RUNSH"
  } >"$HEP/tail.sh"
  bash "$HEP/tail.sh" >"$HEP/out" 2>&1 || rc=$?
  printf '%s' "$rc"
}

# (A) A truncated run is RED. Nothing failed, but almost nothing ran either.
hep_rc=$(_hep_exit_path 1 0)
if [ "$hep_rc" -ne 0 ] && grep -qF "the floor is $HEP_MIN" "$HEP/out"; then
  echo "  ✓ a run below the assertion floor exits non-zero with the count in it"
  PASS=$((PASS + 1))
else
  echo "  ✗ floor: 1 passing assertion should be a red run (rc=$hep_rc)"
  sed 's/^/      /' "$HEP/out"
  FAIL=$((FAIL + 1))
fi

# (B) POSITIVE CONTROL for (A): a complete, clean run is still GREEN. Without
#     this, a floor that failed unconditionally would look like a pass above.
hep_rc=$(_hep_exit_path "$HEP_MIN" 0)
if [ "$hep_rc" -eq 0 ] && grep -qF "Result: $HEP_MIN passed, 0 failed" "$HEP/out"; then
  echo "  ✓ a full run with no failures still exits 0 and prints its count"
  PASS=$((PASS + 1))
else
  echo "  ✗ floor: a run AT the floor with 0 failures should exit 0 (rc=$hep_rc)"
  sed 's/^/      /' "$HEP/out"
  FAIL=$((FAIL + 1))
fi

# (C) REGRESSION: exactly 256 failures must not wrap to success. This is the one
#     value in the suite's reachable range where `exit "$FAIL"` reported PASS.
hep_rc=$(_hep_exit_path 100000 256)
if [ "$hep_rc" -eq 1 ] && grep -qF "Result: 100000 passed, 256 failed" "$HEP/out"; then
  echo "  ✓ 256 failing assertions exit 1, not 0 (status no longer wraps mod 256)"
  PASS=$((PASS + 1))
else
  echo "  ✗ 256 failures must exit 1 and still print the count (rc=$hep_rc)"
  sed 's/^/      /' "$HEP/out"
  FAIL=$((FAIL + 1))
fi

# (D) The ordinary case keeps working: any non-zero failure count is exit 1.
hep_rc=$(_hep_exit_path 100000 1)
if [ "$hep_rc" -eq 1 ]; then
  echo "  ✓ a single failing assertion exits 1"
  PASS=$((PASS + 1))
else
  echo "  ✗ one failure should exit 1 (rc=$hep_rc)"
  sed 's/^/      /' "$HEP/out"
  FAIL=$((FAIL + 1))
fi

rm -rf "$HEP"
reset_repo

# --- shellcheck CI covers every shell file in the tree, by discovery ---------
# .github/workflows/shellcheck.yml used to name its targets by hand, and three
# shipped scripts had never been added to that list: githooks/lib/check-gitleaks
# (installed by --gitleaks-hook), scaffold-audit and scaffold-config (installed
# into every consumer's .githooks/lib/). Adding a script did not add it to the
# check, and nothing said so, so the next scanner would have shipped unlinted
# too. These assertions run the workflow's REAL discovery loop with `shellcheck`
# stubbed out, and read the argv it would have been handed.
SCC=$(mktemp -d)
awk -v step="      - name: Discover and check every shell file in the tree" '
  $0 == step { found = 1 }
  found && /run: \|/ { inrun = 1; next }
  inrun {
    if ($0 ~ /^[[:space:]]*$/) { print ""; next }
    if ($0 !~ /^          /) exit
    sub(/^          /, "")
    print
  }
' "$SCAFFOLD_DIR/.github/workflows/shellcheck.yml" >"$SCC/discover.sh"
# The stub records argv instead of linting: the question here is COVERAGE (which
# files the job hands to shellcheck), not whether those files are clean, and it
# keeps the case deterministic on a machine with no shellcheck installed.
cat >"$SCC/shellcheck" <<'STUB'
#!/bin/sh
printf '%s\n' "$@" >"$SCC_ARGV"
exit 0
STUB
chmod +x "$SCC/shellcheck"
scc_rc=0
( cd "$SCAFFOLD_DIR" && SCC_ARGV="$SCC/argv" PATH="$SCC:$PATH" bash -e "$SCC/discover.sh" ) \
  >"$HOOK_OUT" 2>&1 || scc_rc=$?

_scc_has() { grep -qxF "$1" "$SCC/argv" 2>/dev/null; }

# (E) the three scripts the hand-written list had always missed.
if [ "$scc_rc" -eq 0 ] \
   && _scc_has githooks/lib/check-gitleaks.template \
   && _scc_has githooks/lib/scaffold-audit.template \
   && _scc_has githooks/lib/scaffold-config.template; then
  echo "  ✓ shellcheck CI discovers the three scripts the hand list never had"
  PASS=$((PASS + 1))
else
  echo "  ✗ shellcheck CI still misses check-gitleaks/scaffold-audit/scaffold-config (rc=$scc_rc)"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi

# (F) NO REGRESSION: everything the hand list did cover is still covered,
#     including the two shapes a naive "*.sh with a shebang" filter would drop
#     (sourced case files carrying only a `# shellcheck shell=` directive, and
#     extensionless *.template hooks).
if _scc_has install.sh && _scc_has tests/run.sh && _scc_has tests/lib/common.sh \
   && _scc_has tests/cases/01-size-patterns.sh \
   && _scc_has githooks/pre-commit.template && _scc_has uninstall.sh; then
  echo "  ✓ discovery still covers every file the hand-written list named"
  PASS=$((PASS + 1))
else
  echo "  ✗ discovery dropped a file the old hand-written list covered"
  sed 's/^/      /' "$SCC/argv" 2>/dev/null || true
  FAIL=$((FAIL + 1))
fi

# (G) and it is a SHELL filter, not "every tracked file": the python3 hooks and
#     the data template must not be handed to shellcheck, which would fail the
#     job on files that are not shell at all.
# `-s` first, so this cannot pass by discovering NOTHING: a negative-only
#     assertion is also satisfied by a job that never ran.
if [ -s "$SCC/argv" ] \
   && ! _scc_has githooks/lib/check-red-green.template \
   && ! _scc_has githooks/lib/check-mutation-diff.template \
   && ! _scc_has githooks/lib/credential-read-patterns.txt.template; then
  echo "  ✓ discovery excludes the python3 hooks and the data template"
  PASS=$((PASS + 1))
else
  echo "  ✗ discovery handed a non-shell file to shellcheck"
  sed 's/^/      /' "$SCC/argv" 2>/dev/null || true
  FAIL=$((FAIL + 1))
fi
rm -rf "$SCC"
reset_repo
