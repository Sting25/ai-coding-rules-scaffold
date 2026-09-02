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

_tg_fixture() {
  local t; t=$(mktemp -d)
  ( cd "$t" && git init --quiet && echo '{"name":"x"}' >package.json \
    && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify "$@" ) >/dev/null 2>&1
  printf '%s' "$t"
}

# (T) a default install (no flag) creates none of the four artifacts:
# stays opt-in.
D=$(_tg_fixture)
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
T=$(_tg_fixture --test-guard)
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

# (T) the installed check is runnable python3 and exits 0 in a repo with no
# tests/ directory (its documented nothing-to-verify path): the positive
# assertion that the artifact executes, not just that no error appeared.
if ( cd "$T" && python3 .githooks/lib/check-red-green --base HEAD ) >"$HOOK_OUT" 2>&1; then
  echo "  ✓ installed check-red-green runs and exits 0 with no tests directory"; PASS=$((PASS + 1))
else
  echo "  ✗ installed check-red-green should exit 0 with no tests directory"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
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
U=$(_tg_fixture --test-guard)
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
  echo "  - skipped check-red-green detection tests (pytest not importable)"
else
  # Base commit: calc.add(), one existing test, and a pytest.ini registering the
  # characterization marker (the scaffold documents registering it there).
  _rg_fixture() {
    local t; t=$(_tg_fixture --test-guard)
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
    printf '%s' "$t"
  }

  # (T) RED, the path a healthy PR takes: HEAD adds calc.mul() and a test for
  #     it. On base calc.mul does not exist, so the new test fails there and the
  #     gate passes, with the accounting line that proves it actually ran.
  RG=$(_rg_fixture)
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
  GG=$(_rg_fixture)
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
  rm -rf "$GG"

  # (T) THE DECLARED EXCEPTION. The same green-on-base test, but marked
  #     @pytest.mark.characterization(reason=...), is allowed and reported as
  #     exempt. Without this the previous case could be satisfied by a check that
  #     rejects every new test, which would make the gate unusable.
  CG=$(_rg_fixture)
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
TGF=$(_tg_fixture --test-guard)
( cd "$TGF" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify --force ) >"$HOOK_OUT" 2>&1
if [ "$(grep -c 'ai-coding-rules-scaffold:test-guard:begin' "$TGF/coding-rules.md")" -eq 1 ] \
   && grep -q 'characterization' "$TGF/coding-rules.md" \
   && [ -f "$TGF/.github/workflows/test-guard.yml" ] \
   && [ -x "$TGF/.githooks/lib/check-red-green" ] \
   && grep -q 'merged:.*test-guard (red-green) section' "$HOOK_OUT"; then
  echo "  ✓ --force without --test-guard keeps the rules section the armed gate depends on"; PASS=$((PASS + 1))
else
  echo "  ✗ --force should re-append the test-guard rules section while the gate is installed"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$TGF"

# (T) a plain re-run of a test-guard project (no flag, no --force) also restores
# the section if it was removed by hand: presence, not the flag, is the gate.
TGR=$(_tg_fixture --test-guard)
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
TGN=$(_tg_fixture)
( cd "$TGN" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify --force ) >"$HOOK_OUT" 2>&1
if ! grep -q 'ai-coding-rules-scaffold:test-guard:begin' "$TGN/coding-rules.md" \
   && cmp -s "$SCAFFOLD_DIR/coding-rules.md" "$TGN/coding-rules.md"; then
  echo "  ✓ a project without the gate still gets no test-guard section on --force"; PASS=$((PASS + 1))
else
  echo "  ✗ a project without the gate should not gain a test-guard section"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$TGN"
