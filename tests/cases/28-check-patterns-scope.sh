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

# cp_clean NAME FILE...: the negative counterpart of cp_run. Asserts the
# POSITIVE outcome of a clean run (exit 0 AND no finding text), not merely that
# one message is absent, so a crash to empty output cannot pass it.
cp_clean() {
  local name=$1; shift
  local rc=0
  printf '%s\0' "$@" | .githooks/lib/check-patterns >"$HOOK_OUT" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "  ✗ $name: check-patterns exited $rc, expected 0"
    sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  elif [ -s "$HOOK_OUT" ] && grep -qE 'structlog|console\.log|Use ' "$HOOK_OUT"; then
    echo "  ✗ $name: exited 0 but reported a finding"
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

# 28k. BUILT-IN FALLBACK PARITY. The `# scaffold-extensions:` header wins, but a
#      pattern file without one falls back to a built-in map. frontend.txt gained
#      `svelte` in its header while the fallback still read `ts tsx js jsx vue`,
#      so on the fallback path every .svelte file (and the {@html} XSS rule with
#      it) went unscanned. Strip the header to force that path and re-scan.
grep -v '^#[[:space:]]*scaffold-extensions:' .forbidden-patterns/frontend.txt >fe-noheader.tmp
mv fe-noheader.tmp .forbidden-patterns/frontend.txt
printf '<p>{@html userInput}</p>\n' >fallback.svelte
git add .forbidden-patterns/frontend.txt fallback.svelte
cp_run "header-less frontend.txt still scans .svelte (fallback parity)" "XSS" fallback.svelte

# 28l. CONTROL for 28k: with the header stripped, an extension the fallback DOES
#      declare must still be scanned, otherwise 28k could pass because the
#      fallback path is broken outright rather than because svelte was added.
printf 'console.log("debug");\n' >fallback.ts
git add fallback.ts
cp_run "header-less frontend.txt still scans .ts (fallback control)" "console.log" fallback.ts
reset_repo

# 28m. THE NEGATIVE FOR 28g/28h, and the reason it is worth writing. 28g and 28h
#      prove the fold makes BAD.PY and BAD.Py reachable. Neither proves the fold
#      stopped there. Case-folding a suffix match is the kind of change that
#      looks obviously safe and occasionally is not: a fold implemented as a
#      case-insensitive substring or a stripped-anchor regex would start
#      matching extensions no header declares, and every one of these files
#      would silently come into scope. The content below WOULD be reported if
#      the file were scanned (`print(` is a backend.txt rule, `console.log` a
#      frontend.txt one), so each assertion fails loudly if the scope widened.
#      Asserts exit 0 AND no finding, so a crash to empty output cannot pass it.
mkdir -p src
printf 'pri''nt("debug")\n'        >src/notes.md
printf 'console.log("debug");\n'   >src/notes.MD
printf 'pri''nt("debug")\n'        >src/data.pyc
printf 'pri''nt("debug")\n'        >src/report.PYTHON
printf 'console.log("debug");\n'   >src/vendor.jsonc
git add src/notes.md src/notes.MD src/data.pyc src/report.PYTHON src/vendor.jsonc
cp_clean "an undeclared extension stays out of scope in every case variant" \
  src/notes.md src/notes.MD src/data.pyc src/report.PYTHON src/vendor.jsonc
reset_repo

# 28n. The control for 28m: the same content in a DECLARED extension is still
#      reported. Without it, 28m would also pass against a check-patterns that
#      had stopped scanning anything at all.
mkdir -p src
printf 'pri''nt("debug")\n' >src/real.PY
git add src/real.PY
cp_run "the same content in a declared extension is still reported (28m control)" "structlog" src/real.PY
reset_repo

# --- a removed pattern file the manifest still records (#159) ---------------
echo ""
echo "check-patterns manifest-recorded config removal (#159):"

# cp_ci_run NAME EXPECT FIXTURE...: cp_run in --ci mode. The removal below is
# invisible precisely on the SERVER side (the file is still on disk for whoever
# untracked it), so these run the same way lint.yml does.
cp_ci_run() {
  local name=$1 expect=$2; shift 2
  local rc=0
  printf '%s\0' "$@" | .githooks/lib/check-patterns --ci >"$HOOK_OUT" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  ✗ $name: check-patterns --ci exited 0, expected a finding"
    sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  elif ! grep -qF "$expect" "$HOOK_OUT"; then
    echo "  ✗ $name: non-zero but missing: $expect"
    sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  else
    echo "  ✓ $name"; PASS=$((PASS + 1))
  fi
}

# cp_ci_silent NAME FIXTURE...: the negative counterpart. Asserts exit 0 AND
# that nothing was said about a missing config, so a guard that reports without
# failing cannot pass as "silent" either.
cp_ci_silent() {
  local name=$1; shift
  local rc=0
  printf '%s\0' "$@" | .githooks/lib/check-patterns --ci >"$HOOK_OUT" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "  ✗ $name: check-patterns --ci exited $rc, expected 0"
    sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  elif grep -qF "is missing" "$HOOK_OUT"; then
    echo "  ✗ $name: exited 0 but reported a missing config"
    sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  else
    echo "  ✓ $name"; PASS=$((PASS + 1))
  fi
}

# 28o. REMOVED, not "never installed". `git rm --cached
#      .forbidden-patterns/backend.txt` leaves the file on disk for whoever ran
#      it, so their hook stays armed, while CI's checkout and every fresh clone
#      have no backend.txt at all. Discovery can only iterate files that exist,
#      so there every backend rule stopped running and check-patterns exited 0
#      with no output anywhere (#159). The install manifest records that the
#      installer wrote the file here, which is exactly what separates a removal
#      from a language this project never had. Reproduce the CI side by deleting
#      the file and scanning in --ci mode: the violation below WOULD be reported
#      with backend.txt present, so a silent exit 0 here is the hole itself.
rm -f .forbidden-patterns/backend.txt
printf 'import os\npri''nt("debug")\n' >removed.py
git add removed.py
cp_ci_run "manifest-recorded backend.txt missing fails closed in CI" \
  ".forbidden-patterns/backend.txt is missing" removed.py
reset_repo

# 28p. THE FALSE POSITIVE THAT WOULD MAKE 28o UNSHIPPABLE. A project that never
#      installed a language has neither the pattern file nor a manifest entry
#      for it, which is the state a --frontend-only install is in for
#      backend.txt, and it must stay silent. Drop both to reach that state.
rm -f .forbidden-patterns/backend.txt
grep -vF '.forbidden-patterns/backend.txt' .githooks/.scaffold-manifest >mf-noentry.tmp
mv mf-noentry.tmp .githooks/.scaffold-manifest
printf 'import os\npri''nt("debug")\n' >never.py
git add never.py
cp_ci_silent "no manifest entry and no file stays silent" never.py

# 28q. The control for 28p: with backend.txt absent AND unrecorded, the other
#      tiers must still scan. Without it 28p would pass just as well against a
#      check-patterns that had stopped reporting anything at all.
printf 'console.log("debug");\n' >never.ts
git add never.ts
cp_ci_run "other tiers still scan while backend.txt is unrecorded" \
  "console.log" never.ts
reset_repo

# 28r. Every install that predates the manifest has no manifest at all, and so
#      does a repo that has run uninstall.sh (it removes the manifest in both
#      modes). Those must fall back to today's behaviour, not start failing.
rm -f .githooks/.scaffold-manifest .forbidden-patterns/backend.txt
printf 'import os\npri''nt("debug")\n' >nomanifest.py
git add nomanifest.py
cp_ci_silent "no manifest at all stays silent" nomanifest.py
reset_repo
