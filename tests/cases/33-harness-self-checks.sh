# shellcheck shell=bash
# cases/33-harness-self-checks.sh: the scaffold's own harness and CI, checked
# by the suite they gate. Sourced into the driver's shell, so PASS/FAIL/
# HOOK_OUT/SCAFFOLD_DIR are in scope.
#
# Every other case file asks "did the scaffold reject the right thing". This one
# asks the question no other case can: "did the suite that answered actually
# run, and does its exit status say so". Two defects lived in tests/run.sh:
#
#   1. No working assertion floor. A case file that stops early (a stray
#      `return`, a guard that turns out false, an edit that drops half the file)
#      takes its assertions with it and the run still prints "0 failed".
#      Measured: prepending `return 0` to cases/07-agent-commit.sh dropped 26
#      assertions and reported "Result: 472 passed, 0 failed", exit 0, green CI.
#      A single global MIN_PASS did not catch it: one number set below the whole
#      suite's total tolerates the loss of any case file smaller than the gap.
#      The floor is now PER CASE FILE, so each file's contribution is
#      individually non-optional.
#   2. `exit "$FAIL"` wrapped. An exit status is taken mod 256, so exactly 256
#      failing assertions exited 0 (and 394 would have exited 138). CI consumes
#      nothing but that status: .github/workflows/test.yml and release.yml both
#      just `run: ./tests/run.sh`, and release.yml's publish job `needs: test`.
#
# (A) to (C) run the REAL harness over a REAL case file in a throwaway copy of
# the tree: the copy is trimmed to two case files, run once intact and once with
# cases/07 gutted exactly as the reproduction above. Feeding the exit path a
# chosen PASS/FAIL, which is all the earlier version of this case did, proves
# the arithmetic and nothing about the guarantee. (F) to (I) still do that for
# the exit STATUS, where a synthetic count is the only way to reach 256.
# Asserting on run.sh's source text would pass against any rewrite that
# reintroduced the hole by another route; running it cannot.

echo "cases/33, the harness checks itself (tests/run.sh, shellcheck.yml)"

RUNSH="$SCAFFOLD_DIR/tests/run.sh"
HEP=$(mktemp -d)

# The floors must be greppable per-case constants, or "bump the number when you
# add assertions" is not a followable instruction.
_hep_floor_of() { sed -n "s/^  \"$1:\([0-9][0-9]*\)\"\$/\1/p" "$RUNSH"; }
HEP_F01=$(_hep_floor_of "01-size-patterns.sh")
HEP_F07=$(_hep_floor_of "07-agent-commit.sh")

# --- (A) to (C): the floor, against a real gutted case file -----------------
# A throwaway copy of the whole tree, trimmed to two case files: cases/01 as the
# intact control and cases/07 as the file to gut. Two files rather than 33 keeps
# this to two short bootstraps instead of two full suites; the mechanism under
# test (per-case floors) is identical at either size, and the run is the real
# tests/run.sh, not a transcription of it.
HEP_TREE="$HEP/tree"
mkdir -p "$HEP_TREE"
( cd "$SCAFFOLD_DIR" && tar cf - --exclude .git --exclude node_modules . ) \
  | ( cd "$HEP_TREE" && tar xf - )
for hep_f in "$HEP_TREE"/tests/cases/*.sh; do
  case "${hep_f##*/}" in
    01-size-patterns.sh | 07-agent-commit.sh) ;;
    *) rm -f "$hep_f" ;;
  esac
done
# Trim the copy's CASE_FLOORS to the two surviving files, keeping their real
# floors, so the copy is a consistent tree rather than one missing its wiring.
awk -v k1="01-size-patterns.sh:$HEP_F01" -v k2="07-agent-commit.sh:$HEP_F07" '
  /^CASE_FLOORS=\(/ { print; printf "  \"%s\"\n  \"%s\"\n", k1, k2; drop = 1; next }
  drop && /^\)/     { print; drop = 0; next }
  drop              { next }
                    { print }
' "$RUNSH" >"$HEP_TREE/tests/run.sh"
chmod +x "$HEP_TREE/tests/run.sh"

# Runs the trimmed copy, writes combined output to $1, echoes the exit status.
_hep_run() {
  local rc=0
  bash "$HEP_TREE/tests/run.sh" >"$1" 2>&1 || rc=$?
  printf '%s' "$rc"
}
# The passing count off a "Result:" line that also says 0 failed. Empty if the
# run failed an assertion or never reached the end.
_hep_clean_count() { sed -n 's/^Result: \([0-9][0-9]*\) passed, 0 failed$/\1/p' "$1"; }

# (A) POSITIVE CONTROL, and it comes first: the trimmed tree is GREEN intact.
#     Without it, the red in (B) could come from the trimming rather than from
#     the gutting, and a floor that failed unconditionally would look correct.
hep_rc=$(_hep_run "$HEP/control.out")
hep_count=$(_hep_clean_count "$HEP/control.out")
if [ "$hep_rc" -eq 0 ] && [ -n "$hep_count" ] \
   && [ "$hep_count" -ge "$((HEP_F01 + HEP_F07))" ]; then
  echo "  ✓ a complete run of the real harness is green ($hep_count assertions)"
  PASS=$((PASS + 1))
else
  echo "  ✗ floor: the intact control tree should be green (rc=$hep_rc)"
  sed 's/^/      /' "$HEP/control.out"
  FAIL=$((FAIL + 1))
fi

# (B) THE REPRODUCTION: `return 0` prepended to a REAL case file. Its assertions
#     do not fail, they never run, and before the per-case floor that was
#     "0 failed" and exit 0. All three halves are asserted: the run is red, it
#     NAMES the file that went quiet, and the rest of the suite still ran and
#     still reported zero failures (so the red is the floor's doing, not a
#     crash and not some other assertion failing).
{ echo "return 0"; cat "$HEP_TREE/tests/cases/07-agent-commit.sh"; } >"$HEP/gutted"
cat "$HEP/gutted" >"$HEP_TREE/tests/cases/07-agent-commit.sh"
hep_rc=$(_hep_run "$HEP/gutted.out")
hep_count=$(_hep_clean_count "$HEP/gutted.out")
if [ "$hep_rc" -ne 0 ] \
   && grep -qF "cases/07-agent-commit.sh: ran 0 assertions, floor is $HEP_F07" "$HEP/gutted.out" \
   && [ -n "$hep_count" ] && [ "$hep_count" -ge "$HEP_F01" ]; then
  echo "  ✓ a case file gutted with 'return 0' is red and named, at 0 failed"
  PASS=$((PASS + 1))
else
  echo "  ✗ floor: a gutted cases/07 must fail the run by name (rc=$hep_rc)"
  sed 's/^/      /' "$HEP/gutted.out"
  FAIL=$((FAIL + 1))
fi

# (C) The one loss the per-case floors cannot see by themselves: a case file
#     that exists but was never wired into CASE_FLOORS contributes nothing and
#     has no floor to miss. run.sh checks that before it installs anything, so
#     this run is a fraction of a second.
: >"$HEP_TREE/tests/cases/99-not-wired.sh"
hep_rc=$(_hep_run "$HEP/unwired.out")
if [ "$hep_rc" -ne 0 ] && grep -qF "cases/99-not-wired.sh" "$HEP/unwired.out" \
   && grep -qF "not in run.sh's CASE_FLOORS list" "$HEP/unwired.out"; then
  echo "  ✓ a case file that is never wired into the list fails the run"
  PASS=$((PASS + 1))
else
  echo "  ✗ an unwired case file should fail the run by name (rc=$hep_rc)"
  sed 's/^/      /' "$HEP/unwired.out"
  FAIL=$((FAIL + 1))
fi

# (D) Every case file that ships carries a floor. This is the same rule (C)
#     enforces at runtime, asserted here against the shipped tree so the failure
#     names the file at review time rather than on the next run.
HEP_UNLISTED=""
for hep_f in "$SCAFFOLD_DIR"/tests/cases/*.sh; do
  hep_n=${hep_f##*/}
  if ! grep -qF "\"$hep_n:" "$RUNSH"; then
    HEP_UNLISTED="$HEP_UNLISTED $hep_n"
  fi
done
if [ -z "$HEP_UNLISTED" ] && [ -n "$HEP_F01" ] && [ -n "$HEP_F07" ]; then
  echo "  ✓ every cases/*.sh file carries a per-case floor in run.sh"
  PASS=$((PASS + 1))
else
  echo "  ✗ case files with no floor in run.sh:$HEP_UNLISTED"
  FAIL=$((FAIL + 1))
fi

# (E) A floor of 0 is a case file the mechanism cannot protect, so there is
#     exactly one permitted: cases/11 is entirely inside a
#     `command -v npm && command -v jq` gate and contributes nothing on a
#     machine without them. Any other zero means someone zeroed a floor instead
#     of finding out why the file went quiet.
HEP_ZERO=$(sed -n 's/^  "\([^"]*\):0"$/\1/p' "$RUNSH" | tr '\n' ' ')
if [ -z "$HEP_ZERO" ] || [ "$HEP_ZERO" = "11-npm-bundle.sh " ]; then
  echo "  ✓ no case file has had its floor zeroed out"
  PASS=$((PASS + 1))
else
  echo "  ✗ unexpected zero floors: $HEP_ZERO"
  FAIL=$((FAIL + 1))
fi

# --- (F) to (I): the exit STATUS -------------------------------------------
# Run run.sh's exit path (everything after the case-sourcing loop) with the
# globals it reads set to the values under test. 256 failures is not reachable
# by gutting a file, so this half stays synthetic. Output lands in $HEP/out.
_hep_exit_path() {
  local p=$1 f=$2 short=$3 total=$4 rc=0
  {
    printf 'set -euo pipefail\nPASS=%s\nFAIL=%s\nSHORT_CASES=%s\nFLOOR_TOTAL=%s\n' \
      "$p" "$f" "'$short'" "$total"
    awk '/^# --- result and exit status/ { found = 1 } found { print }' "$RUNSH"
  } >"$HEP/tail.sh"
  bash "$HEP/tail.sh" >"$HEP/out" 2>&1 || rc=$?
  printf '%s' "$rc"
}

# (F) A clean, complete run is green and prints its count.
hep_rc=$(_hep_exit_path 500 0 "" 400)
if [ "$hep_rc" -eq 0 ] && grep -qF "Result: 500 passed, 0 failed" "$HEP/out"; then
  echo "  ✓ a full run with no failures exits 0 and prints its count"
  PASS=$((PASS + 1))
else
  echo "  ✗ a complete run with 0 failures should exit 0 (rc=$hep_rc)"
  sed 's/^/      /' "$HEP/out"
  FAIL=$((FAIL + 1))
fi

# (G) The floors also sum to a total, so a run under it is red even if no single
#     file reported itself short (a case list truncated at the tail, say).
hep_rc=$(_hep_exit_path 1 0 "" 400)
if [ "$hep_rc" -ne 0 ] && grep -qF "the case floors sum to 400" "$HEP/out"; then
  echo "  ✓ a run below the summed floor is red with both numbers in it"
  PASS=$((PASS + 1))
else
  echo "  ✗ 1 assertion against a summed floor of 400 should be red (rc=$hep_rc)"
  sed 's/^/      /' "$HEP/out"
  FAIL=$((FAIL + 1))
fi

# (H) REGRESSION: exactly 256 failures must not wrap to success. This is the one
#     value in the suite's reachable range where `exit "$FAIL"` reported PASS.
hep_rc=$(_hep_exit_path 100000 256 "" 400)
if [ "$hep_rc" -eq 1 ] && grep -qF "Result: 100000 passed, 256 failed" "$HEP/out"; then
  echo "  ✓ 256 failing assertions exit 1, not 0 (status no longer wraps mod 256)"
  PASS=$((PASS + 1))
else
  echo "  ✗ 256 failures must exit 1 and still print the count (rc=$hep_rc)"
  sed 's/^/      /' "$HEP/out"
  FAIL=$((FAIL + 1))
fi

# (I) The ordinary case keeps working: any non-zero failure count is exit 1.
hep_rc=$(_hep_exit_path 100000 1 "" 400)
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

# (J) the three scripts the hand-written list had always missed.
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

# (K) NO REGRESSION: everything the hand list did cover is still covered,
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

# (L) and it is a SHELL filter, not "every tracked file": the python3 hooks and
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
