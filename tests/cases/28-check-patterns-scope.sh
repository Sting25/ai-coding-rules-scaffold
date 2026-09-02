# shellcheck shell=bash
# cases/28-check-patterns-scope.sh, CHECK_PATTERNS_INCLUDE / CHECK_PATTERNS_EXCLUDE
# (#149). Sourced into the driver's shell. Exercises check-patterns directly with
# a NUL list on stdin (the same way case 10 does), since the pre-commit hook
# never sets either variable. Every case asserts the POSITIVE outcome (the file
# that should be flagged IS flagged and the exit is non-zero), never only the
# absence of the other file.
echo ""
echo "check-patterns INCLUDE/EXCLUDE scoping (#149):"

# Fixtures: one backend.txt violation, one frontend.txt violation. Staged so
# check-patterns' `git show :0:` scan can see them.
printf 'print("debug")\n' >scope_debug.py
printf 'console.log("debug");\n' >scope_debug.ts
git add scope_debug.py scope_debug.ts

# run_cp <name> <expected-flagged> <expected-clean> [<expected stderr substring>]
# Environment for the run comes from the CP_ENV array (env(1) arguments), so
# values with spaces survive and nothing leaks into the driver's shell.
CP_ENV=()
run_cp() {
  local name=$1 want=$2 clean=$3 warn=${4:-} rc=0
  printf '%s\0' scope_debug.py scope_debug.ts \
    | env "${CP_ENV[@]}" .githooks/lib/check-patterns >"$HOOK_OUT" 2>&1 || rc=$?
  if [ -n "$want" ] && ! grep -qF "$want" "$HOOK_OUT"; then
    echo "  ✗ $name: $want was not flagged"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  elif [ -n "$want" ] && [ "$rc" -eq 0 ]; then
    echo "  ✗ $name: $want flagged but exit was 0"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  elif [ -z "$want" ] && [ "$rc" -ne 0 ]; then
    echo "  ✗ $name: expected exit 0, got $rc"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  elif [ -n "$clean" ] && grep -qF "$clean" "$HOOK_OUT"; then
    echo "  ✗ $name: $clean was flagged, expected out of scope"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  elif [ -n "$warn" ] && ! grep -qF "$warn" "$HOOK_OUT"; then
    echo "  ✗ $name: expected warning missing: $warn"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  else
    echo "  ✓ $name"; PASS=$((PASS + 1))
  fi
}

# 28a. Baseline: both unset, both files flagged (unchanged default behavior).
CP_ENV=(-u CHECK_PATTERNS_INCLUDE -u CHECK_PATTERNS_EXCLUDE)
run_cp "unset: backend rule fires" scope_debug.py ""
run_cp "unset: frontend rule fires" scope_debug.ts ""

# 28b. INCLUDE=backend.txt: the .py violation fires, the .ts one is out of scope.
CP_ENV=(CHECK_PATTERNS_INCLUDE=backend.txt)
run_cp "INCLUDE=backend.txt scans only backend rules" scope_debug.py scope_debug.ts

# 28c. EXCLUDE=backend.txt: the .ts violation fires, the .py one is skipped.
CP_ENV=(CHECK_PATTERNS_EXCLUDE=backend.txt)
run_cp "EXCLUDE=backend.txt skips backend rules" scope_debug.ts scope_debug.py

# 28d. Space-separated lists: INCLUDE naming both files scans both.
CP_ENV=(CHECK_PATTERNS_INCLUDE="backend.txt frontend.txt")
run_cp "INCLUDE with two names scans both" scope_debug.py ""
grep -qF scope_debug.ts "$HOOK_OUT" || { echo "  ✗ INCLUDE with two names missed frontend"; FAIL=$((FAIL + 1)); }

# 28e. Whole-name match: `backend` (no .txt) selects nothing and warns loudly
#      instead of scanning nothing silently. Exit 0 (no violations were scanned).
CP_ENV=(CHECK_PATTERNS_INCLUDE=backend)
run_cp "INCLUDE matching no file warns, exit 0" "" scope_debug.py "matched no .forbidden-patterns"

# 28f. Reinstall preserves the contract (#149's actual failure mode): after a
#      plain install.sh re-run refreshes the scaffold-owned check-patterns, the
#      INCLUDE filter still works. Also asserts the variable name is present in
#      the installed file, so a future template edit that drops it fails here.
"$SCAFFOLD_DIR/install.sh" --both --all-langs --no-verify >/dev/null 2>&1
git add scope_debug.py scope_debug.ts
if [ "$(grep -c CHECK_PATTERNS_INCLUDE .githooks/lib/check-patterns)" -ge 1 ]; then
  echo "  ✓ reinstall keeps CHECK_PATTERNS_INCLUDE in check-patterns"; PASS=$((PASS + 1))
else
  echo "  ✗ reinstall dropped CHECK_PATTERNS_INCLUDE from check-patterns"; FAIL=$((FAIL + 1))
fi
CP_ENV=(CHECK_PATTERNS_INCLUDE=backend.txt)
run_cp "INCLUDE still honored after reinstall" scope_debug.py scope_debug.ts

reset_repo

# --- check-patterns config integrity ---------------------------------------
# Everything below invokes check-patterns directly with a NUL list, like the
# scoping cases above, so each assertion pins check-patterns' own verdict rather
# than whichever sibling check happens to reject the same commit first.
echo ""
echo "check-patterns config integrity:"

# cp_run <name> <expect-substring> <fixture...>: the fixtures must be STAGED
# already; asserts check-patterns exits non-zero AND says the expected thing.
cp_run() {
  local name=$1 expect=$2; shift 2
  local rc=0
  printf '%s\0' "$@" | .githooks/lib/check-patterns >"$HOOK_OUT" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  ✗ $name: check-patterns exited 0, expected a finding"
    sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  elif ! grep -qF "$expect" "$HOOK_OUT"; then
    echo "  ✗ $name: non-zero but missing: $expect"
    sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  else
    echo "  ✓ $name"; PASS=$((PASS + 1))
  fi
}

# 28g. CASE-INSENSITIVE EXTENSIONS. The extension match was case-SENSITIVE, so
#      renaming a file to `src/BAD.PY` matched no arm of backend.txt, was dropped
#      before the scan, and committed with zero findings at the hook AND at the
#      whole-tree CI gate. check-filenames has folded case with tr for exactly
#      this reason; check-patterns now does too.
mkdir -p src
printf 'import os\npri''nt("debug")\n' >src/BAD.PY
git add src/BAD.PY
cp_run "upper-case .PY extension is scanned" "structlog" src/BAD.PY
reset_repo

# 28h. Mixed case too (.Py), so the fix is a fold and not a second hard-coded arm.
mkdir -p src
printf 'import os\npri''nt("debug")\n' >src/Mixed.Py
git add src/Mixed.Py
cp_run "mixed-case .Py extension is scanned" "structlog" src/Mixed.Py
reset_repo

# 28i. GUTTED CONFIG FAILS CLOSED. Replacing backend.txt with just its header
#      deleted every backend rule in one commit while dodging the orchestrator's
#      deletion guard (which only sees --diff-filter=D), and check-patterns
#      returned 0 with no output at all. check-secrets has failed closed on the
#      same shape since 3ef4ad9; check-patterns now matches it.
printf '# scaffold-extensions: py\n' >.forbidden-patterns/backend.txt
printf 'import os\npri''nt("debug")\n' >gutted.py
git add .forbidden-patterns/backend.txt gutted.py
cp_run "gutted backend.txt fails closed" "has no patterns" gutted.py
reset_repo

# 28j. …and a config whose every rule is an invalid ERE is equally disabled, so
#      it fails closed on the same reasoning rather than scanning for nothing.
printf '# scaffold-extensions: py\n[unclosed\tbroken one\n(also unclosed\tbroken two\n' \
  >.forbidden-patterns/backend.txt
printf 'import os\npri''nt("debug")\n' >allbad.py
git add .forbidden-patterns/backend.txt allbad.py
cp_run "backend.txt with only invalid regexes fails closed" "has no valid patterns" allbad.py
reset_repo

