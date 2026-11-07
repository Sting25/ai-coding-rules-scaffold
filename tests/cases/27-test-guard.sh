# shellcheck shell=bash
# cases/27-test-guard.sh: the opt-in red-green test-integrity gate
# (--test-guard, #140 item 2, plus the advisory mutation layer from #145).
# Four artifacts, three copy policies: .githooks/lib/check-red-green and
# .githooks/lib/check-mutation-diff are both scaffold-owned (cp_scaffold +
# mkx, refreshed on upgrade), test-guard.yml is a drift-preserving CI
# workflow (cp_scaffold_preserve; the drift semantics themselves are proven
# by cases/21's _wd_case, not re-proven here), and the rules section is an
# append-if-marker-absent merge into user-owned coding-rules.md, the same
# pattern as install-claude.sh's CLAUDE.md merge, so a re-run must never
# append twice. check-mutation-diff's own honesty contract is exercised
# directly below: verify_mutmut() runs before anything else in main(),
# including the "nothing to mutate" early return, so in this suite's
# environment, which has no mutmut installed (measured, not assumed),
# invoking the installed check with a real --base must exit 2 with a
# distinctive "mutmut is not importable" message, never a false 0. Sourced
# into the driver's shell, so PASS/FAIL/SCAFFOLD_DIR/HOOK_OUT are already
# in scope.

echo "cases/27: --test-guard opt-in red-green gate (#140)"

# The inner directory var is __tg_dir, not "t": _rg_fixture below also
# declares `local t`, and calling `_tg_fixture t ...` from inside it would
# otherwise let bash's dynamic scoping shadow the caller's `t` with this
# function's own (see cases/18-doctor.sh's doc_project for the measured
# reproduction of that failure mode).
_tg_fixture() {
  local __tg_var=$1 __tg_dir; shift
  fixture_repo __tg_dir
  echo '{"name":"x"}' >"$__tg_dir/package.json"
  fixture_install "$__tg_dir" --frontend --no-verify "$@"
  printf -v "$__tg_var" '%s' "$__tg_dir"
}

# (T) a default install (no flag) creates none of the four artifacts:
# stays opt-in.
_tg_fixture D
if [ ! -e "$D/.githooks/lib/check-red-green" ] && [ ! -e "$D/.githooks/lib/check-mutation-diff" ] \
   && [ ! -e "$D/.github/workflows/test-guard.yml" ] \
   && ! grep -q 'ai-coding-rules-scaffold:test-guard:begin' "$D/coding-rules.md"; then
  echo "  ✓ a default install creates no test-guard artifacts"; PASS=$((PASS + 1))
else
  echo "  ✗ a default install should create no test-guard artifacts"; FAIL=$((FAIL + 1))
fi
rm -rf "$D"

# (T) --test-guard installs all four: both checks (executable,
# byte-identical to their shipped templates), the workflow (byte-identical),
# and the rules section appended to coding-rules.md exactly once, with the
# original coding-rules.md content still in place above it.
_tg_fixture T --test-guard
if [ -x "$T/.githooks/lib/check-red-green" ] \
   && cmp -s "$SCAFFOLD_DIR/githooks/lib/check-red-green.template" "$T/.githooks/lib/check-red-green" \
   && [ -x "$T/.githooks/lib/check-mutation-diff" ] \
   && cmp -s "$SCAFFOLD_DIR/githooks/lib/check-mutation-diff.template" "$T/.githooks/lib/check-mutation-diff" \
   && cmp -s "$SCAFFOLD_DIR/.github/workflows/test-guard.yml.template" "$T/.github/workflows/test-guard.yml" \
   && grep -q '^# Coding rules$' "$T/coding-rules.md" \
   && [ "$(grep -c 'ai-coding-rules-scaffold:test-guard:begin' "$T/coding-rules.md")" -eq 1 ]; then
  echo "  ✓ --test-guard installs both checks, the workflow, and the rules section"; PASS=$((PASS + 1))
else
  echo "  ✗ --test-guard should install both checks + workflow + appended rules section"; FAIL=$((FAIL + 1))
fi

# (T) the installed check is runnable python3 and, with a resolvable base and no
# test files changed, exits 0 reporting `empty`: the positive assertion that the
# artifact executes, not just that no error appeared. HEAD must resolve (an
# unresolvable base is exit 2), so the fixture gets an empty initial commit.
git -C "$T" commit -q --allow-empty --no-verify -m init  # scaffold-allow: test fixture
if ( cd "$T" && python3 .githooks/lib/check-red-green --base HEAD ) >"$HOOK_OUT" 2>&1 \
   && grep -qF "gate=red-green status=empty" "$HOOK_OUT"; then
  echo "  ✓ installed check-red-green runs and exits 0 as empty when no test files changed"; PASS=$((PASS + 1))
else
  echo "  ✗ installed check-red-green should exit 0 with status=empty when no test files changed"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi

# (T) the installed check-mutation-diff is runnable python3 and honors its
# documented exit contract: verify_mutmut() runs before anything else in
# main(), including the "nothing to mutate" early return, so with mutmut
# not importable it must exit 2 naming that reason, never a false 0 or a
# generic crash. Guarded on a live re-check of the assumption (this suite's
# environment has no mutmut installed) so environment drift fails loudly
# here instead of silently validating the wrong path.
if python3 -c 'import mutmut' >/dev/null 2>&1; then
  echo "  ✗ check-mutation-diff honesty-contract assertion assumes mutmut is not importable here, but it now is; this assertion needs the other deterministic path"; FAIL=$((FAIL + 1))
else
  mut_rc=0
  ( cd "$T" && python3 .githooks/lib/check-mutation-diff --base HEAD ) >"$HOOK_OUT" 2>&1 || mut_rc=$?
  if [ "$mut_rc" -eq 2 ] && grep -q 'mutmut is not importable' "$HOOK_OUT"; then
    echo "  ✓ installed check-mutation-diff exits 2 naming mutmut not importable"; PASS=$((PASS + 1))
  else
    echo "  ✗ installed check-mutation-diff should exit 2 naming mutmut not importable (got exit $mut_rc)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
fi

# (T) an uncaught Python exception in either gate is a tooling crash: exit 2 with
# `internal error` and the traceback, never exit 1 (the gate's "declined (size)" /
# "found a decline" code, which test-guard.yml reads as a pass). The crash is
# injected into a copy of the installed lib/ (main() is replaced by an IndexError),
# so the installed files are untouched. A crash ends before gate-status, like the
# timeout branch: the contract is a non-zero exit, not a status line.
CRASH="$(mktemp -d)"
cp -R "$T/.githooks/lib" "$CRASH/lib"
for crash_g in check-mutation-diff check-red-green; do
  python3 - "$CRASH/lib/$crash_g" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
assert "rc = main();" in s
open(p, "w").write(s.replace("rc = main();", "rc = [][0];"))
PYEOF
  crash_rc=0
  ( cd "$T" && python3 "$CRASH/lib/$crash_g" --base HEAD ) >"$HOOK_OUT" 2>&1 || crash_rc=$?
  if [ "$crash_rc" -eq 2 ] && grep -qF "$crash_g internal error, IndexError" "$HOOK_OUT" \
     && grep -qF "Traceback (most recent call last)" "$HOOK_OUT"; then
    echo "  ✓ $crash_g: an uncaught exception exits 2 with 'internal error' and a traceback"; PASS=$((PASS + 1))
  else
    echo "  ✗ $crash_g: an uncaught exception should exit 2 with 'internal error' and a traceback (got exit $crash_rc)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
done
# (T) a refusal-log call that itself raises (a bad bash path) must not change the gate's
# exit code (#268): the crash stays exit 2 and a decline stays exit 1, each with one
# stderr warning, never Python's own exit 1 with a traceback. The failure is injected
# into copies of the pristine installed gates (the first loop already rewrote its
# copies; the gate looks for refusal-log beside itself).
[ -f "$CRASH/lib/refusal-log" ] || { cp "$SCAFFOLD_DIR/githooks/lib/refusal-log.template" "$CRASH/lib/refusal-log"; chmod +x "$CRASH/lib/refusal-log"; }
for log_g in check-mutation-diff check-red-green; do
  for log_v in crash decline; do
    if [ "$log_v" = crash ]; then log_inj='rc = [][0];'; log_want=2; else log_inj='rc = 1;'; log_want=1; fi
    python3 - "$T/.githooks/lib/$log_g" "$CRASH/lib/$log_g-$log_v" "$log_inj" <<'PYEOF'
import sys
s = open(sys.argv[1]).read()
for old, new in (("rc = main();", sys.argv[3]), ('_B = shutil.which("bash")', '_B = "/nonexistent/bash"')):
    assert old in s
    s = s.replace(old, new)
open(sys.argv[2], "w").write(s)
PYEOF
    log_rc=0
    ( cd "$T" && python3 "$CRASH/lib/$log_g-$log_v" --base HEAD ) >"$HOOK_OUT" 2>&1 || log_rc=$?
    if [ "$log_rc" -eq "$log_want" ] && grep -qF "refusal-log failed" "$HOOK_OUT"; then
      echo "  ✓ $log_g ($log_v): a failing refusal-log call keeps exit $log_want and warns on stderr"; PASS=$((PASS + 1))
    else
      echo "  ✗ $log_g ($log_v): a failing refusal-log call should keep exit $log_want and warn (got exit $log_rc)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
    fi
  done
done
rm -rf "$CRASH"

# (T) a re-run with the same flag appends nothing: the marker section must
# appear exactly once afterwards, and the run must not back coding-rules.md
# up (nothing was replaced).
( cd "$T" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify --test-guard ) >"$HOOK_OUT" 2>&1
if [ "$(grep -c 'ai-coding-rules-scaffold:test-guard:begin' "$T/coding-rules.md")" -eq 1 ] \
   && [ ! -e "$T/coding-rules.md.scaffold-bak" ]; then
  echo "  ✓ a re-run never appends the rules section twice"; PASS=$((PASS + 1))
else
  echo "  ✗ a re-run should leave exactly one appended rules section"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$T"

# (T) uninstall.sh removes the unmodified checks and workflow, and leaves
# coding-rules.md (user-owned) with the appended section intact.
_tg_fixture U --test-guard
( cd "$U" && "$SCAFFOLD_DIR/uninstall.sh" ) >"$HOOK_OUT" 2>&1
if [ ! -e "$U/.githooks/lib/check-red-green" ] && [ ! -e "$U/.githooks/lib/check-mutation-diff" ] \
   && [ ! -e "$U/.github/workflows/test-guard.yml" ] \
   && grep -q 'ai-coding-rules-scaffold:test-guard:begin' "$U/coding-rules.md"; then
  echo "  ✓ uninstall.sh removes both checks + workflow, keeps the user-owned rules file"; PASS=$((PASS + 1))
else
  echo "  ✗ uninstall.sh should remove both checks + workflow and keep coding-rules.md"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$U"

# --- check-red-green DETECTION -------------------------------------------
# Everything above only proves check-red-green is delivered and that it exits 0
# on its documented "no tests/ directory" path. Its actual verdict logic was
# never executed by this suite: replacing main()'s body with `return 0` left the
# run at 394 passed / 0 failed, so the gate that is supposed to reject a
# green-on-base test could have been dead code and nothing would have said so.
#
# The three cases below build a real two-commit repo (base = calc.add only,
# HEAD = the change under test) and run the INSTALLED check against the base
# commit, asserting the POSITIVE artifact each path is supposed to produce, not
# just an exit code, the mutant above exits 0 silently, so an exit-only
# assertion would still pass against it.
#
# Needs pytest, since the check drives pytest to classify each new test. The
# assumption is re-checked live rather than assumed, and a missing pytest skips
# loudly instead of quietly reporting green.
if ! python3 -c 'import pytest' >/dev/null 2>&1; then
  # Counted, so the case's floor holds without pytest: the block below runs 5
  # assertions (accept red, --max-new, reject green-on-base, its class trailer,
  # and the characterization exemption).
  echo "  - SKIP: pytest not importable, so check-red-green's 5 detection assertions did NOT run"
  SKIP=$((SKIP + 5))
else
  # Base commit: calc.add(), one existing test, and a pytest.ini registering the
  # characterization marker (the scaffold documents registering it there).
  _rg_fixture() {
    local __rg_var=$1 t
    _tg_fixture t --test-guard
    (
      cd "$t" || exit 1
      git config user.email "test@test.local"
      git config user.name "Scaffold Test"
      mkdir -p tests
      printf 'def add(a, b):\n    return a + b\n' >calc.py
      printf '[pytest]\nmarkers =\n    characterization: passes against the base branch by design; give a reason\n' >pytest.ini
      printf 'import calc\n\n\ndef test_add_base():\n    assert calc.add(1, 1) == 2\n' >tests/test_base.py
      git add -A && git commit --quiet -m base --no-verify  # scaffold-allow: test fixture
    ) >/dev/null 2>&1
    printf -v "$__rg_var" '%s' "$t"
  }

  # (T) RED, the path a healthy PR takes: HEAD adds calc.mul() and a test for
  #     it. On base calc.mul does not exist, so the new test fails there and the
  #     gate passes, with the accounting line that proves it actually ran.
  _rg_fixture RG
  (
    cd "$RG" || exit 1
    printf 'def add(a, b):\n    return a + b\n\n\ndef mul(a, b):\n    return a * b\n' >calc.py
    printf 'import calc\n\n\ndef test_mul():\n    assert calc.mul(2, 3) == 6\n' >tests/test_mul.py
    git add -A && git commit --quiet -m feat --no-verify  # scaffold-allow: test fixture
  ) >/dev/null 2>&1
  rg_rc=0
  ( cd "$RG" && python3 .githooks/lib/check-red-green --base HEAD~1 ) >"$HOOK_OUT" 2>&1 || rg_rc=$?
  if [ "$rg_rc" -eq 0 ] && grep -qF "red-green OK" "$HOOK_OUT" \
     && grep -qF "red on base, as required" "$HOOK_OUT"; then
    echo "  ✓ check-red-green accepts a new test that fails on base"; PASS=$((PASS + 1))
  else
    echo "  ✗ check-red-green should accept a red-on-base test with an accounting line (got exit $rg_rc)"
    sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi

  # (T) --max-new: the same fixture, with the budget set below the number of new
  #     tests, must be refused rather than silently re-running them all.
  rg_rc=0
  ( cd "$RG" && python3 .githooks/lib/check-red-green --base HEAD~1 --max-new 0 ) >"$HOOK_OUT" 2>&1 || rg_rc=$?
  if [ "$rg_rc" -eq 1 ] && grep -qF "exceeds --max-new=0" "$HOOK_OUT"; then
    echo "  ✓ check-red-green refuses a diff over --max-new"; PASS=$((PASS + 1))
  else
    echo "  ✗ check-red-green should exit 1 naming --max-new (got exit $rg_rc)"
    sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
  rm -rf "$RG"

  # (T) GREEN-ON-BASE, the whole point of the gate: HEAD adds a test for
  #     behaviour that already worked and changes no source. It passes against
  #     base, so it is not evidence for the change and must be REJECTED, naming
  #     the offending node ID.
  _rg_fixture GG
  (
    cd "$GG" || exit 1
    printf 'import calc\n\n\ndef test_add_again():\n    assert calc.add(2, 2) == 4\n' >tests/test_green.py
    git add -A && git commit --quiet -m greentest --no-verify  # scaffold-allow: test fixture
  ) >/dev/null 2>&1
  rg_rc=0
  ( cd "$GG" && python3 .githooks/lib/check-red-green --base HEAD~1 ) >"$HOOK_OUT" 2>&1 || rg_rc=$?
  if [ "$rg_rc" -eq 1 ] && grep -qF "green-on-base: tests/test_green.py::test_add_again" "$HOOK_OUT"; then
    echo "  ✓ check-red-green rejects a new test that passes on base"; PASS=$((PASS + 1))
  else
    echo "  ✗ check-red-green should exit 1 naming the green-on-base test (got exit $rg_rc)"
    sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
  # #259: a finding (exit 1) is class (a); the trailer is the last line of the output.
  if [ "$(tail -n 1 "$HOOK_OUT")" = "refusal class (a): this check failed on your own change. Fix the file, never the gate." ]; then
    echo "  ✓ the green-on-base refusal ends with the class (a) trailer"; PASS=$((PASS + 1))
  else
    echo "  ✗ the green-on-base refusal should end with the class (a) trailer"
    sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
  rm -rf "$GG"

  # (T) THE DECLARED EXCEPTION. The same green-on-base test, but marked
  #     @pytest.mark.characterization(reason=...), is allowed and reported as
  #     exempt. Without this the previous case could be satisfied by a check that
  #     rejects every new test, which would make the gate unusable.
  _rg_fixture CG
  (
    cd "$CG" || exit 1
    {
      printf 'import pytest\n\nimport calc\n\n\n'
      printf '@pytest.mark.characterization(reason="pinning add before refactor")\n'
      printf 'def test_add_pinned():\n    assert calc.add(2, 2) == 4\n'
    } >tests/test_char.py
    git add -A && git commit --quiet -m chartest --no-verify  # scaffold-allow: test fixture
  ) >/dev/null 2>&1
  rg_rc=0
  ( cd "$CG" && python3 .githooks/lib/check-red-green --base HEAD~1 ) >"$HOOK_OUT" 2>&1 || rg_rc=$?
  if [ "$rg_rc" -eq 0 ] && grep -qF "exempt (characterization): tests/test_char.py::test_add_pinned" "$HOOK_OUT"; then
    echo "  ✓ check-red-green exempts a declared characterization test"; PASS=$((PASS + 1))
  else
    echo "  ✗ check-red-green should exempt the characterization-marked test (got exit $rg_rc)"
    sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
  rm -rf "$CG"
fi

# (T) --force must not leave the docs and the gate disagreeing (audit
# code-install-policy-3). coding-rules.md is cp_safe (user-owned), so --force
# replaces it with the shipped copy, which carries no test-guard section. The
# append used to be gated on THIS run's --test-guard flag, and a plain re-run
# passes TEST_GUARD=0 even for a project that installed the gate long ago:
# measured, `install.sh --test-guard` then `install.sh --force` took the marker
# count from 1 to 0 while test-guard.yml and check-red-green stayed on disk and
# scaffold-doctor.sh still said "0 gaps". CI went on failing PRs over a
# characterization-marker contract that had vanished from the document the
# agents read. The append is now gated on the gate being PRESENT, so the same
# run that removes the section puts it back.
_tg_fixture TGF --test-guard
( cd "$TGF" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify --force-all ) >"$HOOK_OUT" 2>&1
if [ "$(grep -c 'ai-coding-rules-scaffold:test-guard:begin' "$TGF/coding-rules.md")" -eq 1 ] \
   && grep -q 'characterization' "$TGF/coding-rules.md" \
   && [ -f "$TGF/.github/workflows/test-guard.yml" ] \
   && [ -x "$TGF/.githooks/lib/check-red-green" ] \
   && grep -q 'merged:.*test-guard (red-green) section' "$HOOK_OUT"; then
  echo "  ✓ --force-all without --test-guard keeps the rules section the armed gate depends on"; PASS=$((PASS + 1))
else
  echo "  ✗ --force-all should re-append the test-guard rules section while the gate is installed"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$TGF"

# (T) a plain re-run of a test-guard project (no flag, no --force) also restores
# the section if it was removed by hand: presence, not the flag, is the gate.
_tg_fixture TGR --test-guard
grep -v 'ai-coding-rules-scaffold:test-guard' "$TGR/coding-rules.md" >"$TGR/cr.tmp" && mv "$TGR/cr.tmp" "$TGR/coding-rules.md"
( cd "$TGR" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1
if [ "$(grep -c 'ai-coding-rules-scaffold:test-guard:begin' "$TGR/coding-rules.md")" -eq 1 ]; then
  echo "  ✓ a plain re-run restores the test-guard section whenever the gate is on disk"; PASS=$((PASS + 1))
else
  echo "  ✗ a plain re-run should restore the test-guard section while the gate is on disk"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$TGR"

# (T) the control: presence-gating must not turn the section on for a project
# that never installed the gate. --force on a plain install leaves coding-rules.md
# exactly as shipped, with no test-guard section.
_tg_fixture TGN
( cd "$TGN" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify --force-all ) >"$HOOK_OUT" 2>&1
if ! grep -q 'ai-coding-rules-scaffold:test-guard:begin' "$TGN/coding-rules.md" \
   && cmp -s "$SCAFFOLD_DIR/coding-rules.md" "$TGN/coding-rules.md"; then
  echo "  ✓ a project without the gate still gets no test-guard section on --force-all"; PASS=$((PASS + 1))
else
  echo "  ✗ a project without the gate should not gain a test-guard section"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$TGN"

# (T) #206: a mutation size decline (script exit 1) is a neutral check run, not a
# red step. The workflow's two steps (mutation, then the neutral check run) have
# their `run:` blocks extracted verbatim, each ending at the next `- name:`, and
# are driven in sequence under `bash -e` (what Actions uses) against a stub
# check-mutation-diff that exits a chosen code, a stub pip, and a stub gh that
# logs one argument per line. The second step runs only when the first wrote
# declined=true to GITHUB_OUTPUT, as its `if:` does, and only it gets a token.
TGW="$SCAFFOLD_DIR/.github/workflows/test-guard.yml.template"
if grep -q 'test-guard / mutation (declined: size)' "$TGW" \
   && grep -q 'conclusion=neutral' "$TGW" \
   && grep -q 'checks: write' "$TGW" \
   && grep -q "if: steps.mutation.outputs.declined == 'true'" "$TGW"; then
  echo "  ✓ the workflow names the neutral check run, grants checks: write, gates it on declined"; PASS=$((PASS + 1))
else
  echo "  ✗ the workflow should name the neutral check run, conclusion=neutral, checks: write and the declined gate"; FAIL=$((FAIL + 1))
fi

TGD=$(mktemp -d)
mkdir -p "$TGD/bin" "$TGD/w/.githooks/lib"
_tg_extract() { # <step name prefix> -> that step's run: block, de-indented
  python3 - "$TGW" "$1" <<'PYEOF2'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"- name: " + re.escape(sys.argv[2]) + r".*?        run: \|\n(.*?)(?=\n      - name:|\Z)", text, re.S)
for line in m.group(1).splitlines():
    print(line[10:] if line.startswith(" " * 10) else line)
PYEOF2
}
_tg_extract 'Mutation testing' >"$TGD/stepA.sh"
_tg_extract 'Post neutral check run' >"$TGD/stepB.sh"
printf '#!/bin/sh\nexit 0\n' >"$TGD/bin/pip"
cat >"$TGD/bin/gh" <<'GHEOF'
#!/bin/sh
printf '%s\n' "$@" >>"$GH_LOG"
exit "${GH_RC:-0}"
GHEOF
chmod +x "$TGD/bin/pip" "$TGD/bin/gh"
_tg_step() { # <script exit code> <gh exit code>; sets TGD_RC (step A), TGD_RCB (step B, -1 if skipped)
  printf 'import os, sys\nopen(os.environ["ENV_LOG"], "w").write(str("GH_TOKEN" in os.environ))\nsys.exit(%s)\n' "$1" >"$TGD/w/.githooks/lib/check-mutation-diff"
  : >"$TGD/summary"; : >"$TGD/gh.log"; : >"$TGD/out"; : >"$TGD/outB"; rm -f "$TGD/env.log"
  TGD_RC=0; TGD_RCB=-1
  ( cd "$TGD/w" && PATH="$TGD/bin:$PATH" ENV_LOG="$TGD/env.log" \
      GITHUB_STEP_SUMMARY="$TGD/summary" GITHUB_OUTPUT="$TGD/out" GITHUB_REPOSITORY=o/r \
      GITHUB_BASE_REF=main BASE_SHA=abc bash -e "$TGD/stepA.sh" ) >"$HOOK_OUT" 2>&1 || TGD_RC=$?
  if grep -qxF 'declined=true' "$TGD/out"; then
    TGD_RCB=0
    ( cd "$TGD/w" && PATH="$TGD/bin:$PATH" GH_RC="$2" GH_LOG="$TGD/gh.log" GITHUB_REPOSITORY=o/r \
        GH_TOKEN=x HEAD_SHA=def DECLINED_PY=true bash -e "$TGD/stepB.sh" ) >"$TGD/outB" 2>&1 || TGD_RCB=$?
  fi
}

_tg_step 1 0
if [ "$TGD_RC" -eq 0 ] && [ "$TGD_RCB" -eq 0 ] && grep -q -- '--max-mutants N' "$TGD/summary" \
   && grep -q 'check-mutation-diff --base origin/main' "$TGD/summary" \
   && grep -q 'gh pr checkout' "$TGD/summary" \
   && grep -qxF 'name=test-guard / mutation (declined: size)' "$TGD/gh.log" \
   && grep -qxF 'status=completed' "$TGD/gh.log" \
   && grep -qxF 'conclusion=neutral' "$TGD/gh.log" \
   && grep -qxF 'head_sha=def' "$TGD/gh.log" \
   && grep -qxF 'output[title]=Mutation check declined (size)' "$TGD/gh.log" \
   && grep -q '^::warning::' "$HOOK_OUT"; then
  echo "  ✓ mutation exit 1 passes, summarises the local command, then posts a neutral check run"; PASS=$((PASS + 1))
else
  echo "  ✗ mutation exit 1 should pass, summarise, warn and post a neutral check run (rc $TGD_RC/$TGD_RCB)"; sed 's/^/      /' "$HOOK_OUT" "$TGD/gh.log"; FAIL=$((FAIL + 1))
fi

# Structural, read off the workflow itself: the harness above never applies the
# YAML env: maps, so a GH_TOKEN added back to the mutation step would pass the
# runtime probe. Slice each step's text (from its name to the next "- name:")
# and assert the token is declared only in the posting step.
tg_step_text() { awk -v start="$1" '
  index($0, start) { on = 1; next }
  on && /^      - name: / { exit }
  on { print }' "$TGW"; }
if ! tg_step_text 'name: Mutation testing (diff-scoped, advisory)' | grep -q 'GH_TOKEN' \
   && tg_step_text 'name: Post neutral check run (mutation declined)' | grep -q 'GH_TOKEN: .*github\.token' \
   && [ "$(cat "$TGD/env.log")" = "False" ]; then
  echo "  ✓ GH_TOKEN is declared only on the posting step, not the mutation step that runs PR code"; PASS=$((PASS + 1))
else
  echo "  ✗ GH_TOKEN must be declared on the posting step only (mutation step runs the PR's code)"; FAIL=$((FAIL + 1))
fi

for _tg_rc in 2 3; do
  _tg_step "$_tg_rc" 0
  if [ "$TGD_RC" -eq "$_tg_rc" ] && [ "$TGD_RCB" -eq -1 ] && [ ! -s "$TGD/gh.log" ] && [ ! -s "$TGD/summary" ]; then
    echo "  ✓ mutation exit $_tg_rc still fails the step with that code and posts no check run"; PASS=$((PASS + 1))
  else
    echo "  ✗ mutation exit $_tg_rc should fail the step with no check run (rc $TGD_RC/$TGD_RCB)"; FAIL=$((FAIL + 1))
  fi
done

_tg_step 0 0
if [ "$TGD_RC" -eq 0 ] && [ "$TGD_RCB" -eq -1 ] && [ ! -s "$TGD/gh.log" ] && [ ! -s "$TGD/summary" ]; then
  echo "  ✓ mutation exit 0 passes the step untouched"; PASS=$((PASS + 1))
else
  echo "  ✗ mutation exit 0 should pass without a summary or check run (rc $TGD_RC/$TGD_RCB)"; FAIL=$((FAIL + 1))
fi

_tg_step 1 1
if [ "$TGD_RC" -eq 0 ] && [ "$TGD_RCB" -eq 0 ] && [ "$(grep -c '^::warning::' "$HOOK_OUT" "$TGD/outB" | awk -F: '{s+=$NF} END {print s}')" -eq 2 ] && [ -s "$TGD/summary" ]; then
  echo "  ✓ a failing check-run call (fork token) degrades to a second warning and exit 0"; PASS=$((PASS + 1))
else
  echo "  ✗ a failing gh call should give two warnings and exit 0 (rc $TGD_RC/$TGD_RCB)"; sed 's/^/      /' "$HOOK_OUT" "$TGD/outB"; FAIL=$((FAIL + 1))
fi
rm -rf "$TGD"
