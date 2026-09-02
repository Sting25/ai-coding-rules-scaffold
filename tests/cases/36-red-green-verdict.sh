# shellcheck shell=bash
# cases/36-red-green-verdict.sh: the --test-guard gate's actual VERDICT.
# Sourced into the driver's shell, so PASS/FAIL/SKIP/SCAFFOLD_DIR/HOOK_OUT are
# already in scope.
#
# WHAT cases/27 DOES NOT COVER. Every functional assertion there hits a guard
# clause that returns before any gate logic runs: check-red-green.template:141
# (`if not pathlib.Path("tests").exists(): return 0`) is 175 lines above the
# only blocking arm, and check-mutation-diff exits at its verify_mutmut()
# pre-check. So the 329 lines that decide PASS or BLOCK — the worktree overlay,
# the new-node-ID difference, the per-test classification, the characterization
# exemption, the `return 1 if failed else 0` at :315 — could regress to an
# unconditional `return 0` (a bad refactor of still_offending, a broken
# `git worktree add`, a pytest node-ID format change) and this whole suite would
# stay green. The commit that added the gate says the real behaviour was
# verified BY HAND and never encoded; this file encodes it.
#
# THREE VERDICTS, on one shared fixture whose base commit ships a deliberately
# WRONG `add(a, b) -> a - b` plus a test pinned to that wrong behaviour:
#   (a) a new test that FAILS on base  -> exit 0. The false-positive direction,
#       and the one that matters most: a gate that blocks honest red-green work
#       gets switched off within a week, so this is the assertion that keeps it
#       usable.
#   (b) a new test that PASSES on base, unmarked -> exit 1, naming the offender.
#       The gate's whole reason to exist (arXiv 2412.14137: generated suites
#       DISCARD the tests that fail, keeping the ones that pass by construction).
#   (c) the same green-on-base test, marked @pytest.mark.characterization
#       -> exit 0. The named exception must actually work, or the gate's only
#       escape hatch is a dead end and (b) becomes unbypassable.
#
# A root conftest.py is what puts the repo root on sys.path so `from calc import
# add` resolves under pytest's rootdir insertion; it is NOT a test path by
# check-red-green's is_test_path(), so it is never overlaid and stays identical
# in the base worktree.
#
# THE PYTEST DEPENDENCY, stated rather than hidden. check-red-green shells out
# to `sys.executable -m pytest`, so these three assertions cannot run without
# pytest importable. .github/workflows/test.yml installs ruff and zizmor but NOT
# pytest, so in CI today this is a counted SKIP that shows up in the driver's
# final Result line, not a silent pass — adding a pinned `pip install pytest`
# step to test.yml is what turns it into real CI coverage.

echo "cases/36: check-red-green's blocking verdict (#140)"

if ! python3 -c 'import pytest' >/dev/null 2>&1; then
  echo "  - SKIP: pytest not importable — check-red-green's 3 verdict assertions did NOT run (add a pinned 'pip install pytest' step to .github/workflows/test.yml to cover this in CI)"
  SKIP=$((SKIP + 3))
else
  # A fixture repo with the --test-guard artifacts installed, one BASE commit,
  # and HEAD == base. Scenarios below add the second commit. Printed as
  # "<dir> <base_sha>" so the caller needs no second git call.
  #
  # The build runs in a subshell so a failed `cd` cannot strand the driver in a
  # temp dir, but its log goes to $HOOK_OUT rather than /dev/null and its status
  # is RETURNED. An earlier revision sent both to /dev/null: a broken install.sh
  # then produced an empty $() and the run died several lines later inside a
  # scenario with `printf: /calc.py: No such file or directory`, which names
  # neither the fixture nor the assertion that did not run. _rg_new below turns
  # that into one labelled failure with the build log attached.
  _rg_fixture() {
    local t rc=0
    t=$(mktemp -d)
    (
      cd "$t" || exit 1
      git init --quiet
      git config user.email "test@test.local"
      git config user.name "Scaffold Test"
      printf '[project]\nname = "rg"\nversion = "0"\n' >pyproject.toml
      : >conftest.py
      mkdir tests
      # The bug the PR under test is pretending to fix.
      printf 'def add(a, b):\n    return a - b\n' >calc.py
      printf 'from calc import add\n\n\ndef test_add_existing():\n    assert add(5, 5) == 0\n' >tests/test_calc.py
      "$SCAFFOLD_DIR/install.sh" --python --no-verify --test-guard
      git add -A
      git commit --quiet -m "base" --no-verify  # scaffold-allow: test fixture
    ) >"$HOOK_OUT" 2>&1 || rc=$?
    # The artifact under test must actually exist: --test-guard silently doing
    # nothing would otherwise surface as three confusing "exit 127" verdicts.
    if [ "$rc" -ne 0 ] || [ ! -f "$t/.githooks/lib/check-red-green" ]; then
      printf 'fixture build failed (rc=%s), .githooks/lib/check-red-green %s\n' \
        "$rc" "$([ -f "$t/.githooks/lib/check-red-green" ] && echo present || echo MISSING)" >>"$HOOK_OUT"
      rm -rf "$t"
      return 1
    fi
    printf '%s %s' "$t" "$(git -C "$t" rev-parse HEAD)"
  }

  # _rg_new: build a fixture and publish it as $_rg_dir/$_rg_base. On failure it
  # books ONE named FAIL with the build log and returns 1, so the caller skips
  # its scenario instead of running assertions against a directory that is not
  # there.
  _rg_new() {
    local out
    if ! out=$(_rg_fixture); then
      echo "  ✗ could not build the red-green fixture repo — this verdict was NOT tested"
      sed 's/^/      /' "$HOOK_OUT"
      FAIL=$((FAIL + 1))
      return 1
    fi
    read -r _rg_dir _rg_base <<<"$out"
  }

  # _rg_run <dir> <base_sha>: run the INSTALLED check (cases/27 proves it is
  # byte-identical to the shipped template) and echo its exit code. Output lands
  # in $HOOK_OUT for the caller to grep, so a verdict can never pass on the exit
  # code alone while the message says something else.
  _rg_run() {
    local rc=0
    ( cd "$1" && python3 .githooks/lib/check-red-green --base "$2" ) >"$HOOK_OUT" 2>&1 || rc=$?
    printf '%s' "$rc"
  }

  # (a) RED on base: HEAD fixes add() and adds a test that could not have passed
  #     before the fix. Must be allowed through.
  if _rg_new; then
    printf 'def add(a, b):\n    return a + b\n' >"$_rg_dir/calc.py"
    printf 'from calc import add\n\n\ndef test_add_existing():\n    assert add(5, 5) == 10\n\n\ndef test_add_is_a_sum():\n    assert add(2, 3) == 5\n' >"$_rg_dir/tests/test_calc.py"
    git -C "$_rg_dir" add -A && git -C "$_rg_dir" commit --quiet -m "fix add, with a red-on-base test" --no-verify  # scaffold-allow: test fixture
    _rg_rc=$(_rg_run "$_rg_dir" "$_rg_base")
    if [ "$_rg_rc" -eq 0 ] && grep -q 'red on base, as required: 1 test' "$HOOK_OUT"; then
      echo "  ✓ a new test that fails on base is allowed through (exit 0, counted red)"
      PASS=$((PASS + 1))
    else
      echo "  ✗ a red-on-base new test must exit 0 and be counted red (got exit $_rg_rc)"
      sed 's/^/      /' "$HOOK_OUT"
      FAIL=$((FAIL + 1))
    fi
    rm -rf "$_rg_dir"
  fi

  # (b) GREEN on base, unmarked: HEAD changes no source and adds a test that
  #     already passes against base. Must be blocked, and must NAME the node ID
  #     — a bare exit 1 is not actionable.
  if _rg_new; then
    printf 'from calc import add\n\n\ndef test_add_existing():\n    assert add(5, 5) == 0\n\n\ndef test_add_five_five():\n    assert add(5, 5) == 0\n' >"$_rg_dir/tests/test_calc.py"
    git -C "$_rg_dir" add -A && git -C "$_rg_dir" commit --quiet -m "add a test that passes on base" --no-verify  # scaffold-allow: test fixture
    _rg_rc=$(_rg_run "$_rg_dir" "$_rg_base")
    if [ "$_rg_rc" -eq 1 ] \
       && grep -q 'green-on-base: tests/test_calc.py::test_add_five_five' "$HOOK_OUT" \
       && grep -q 'PASS against' "$HOOK_OUT"; then
      echo "  ✓ a new test that passes on base is blocked, naming the offending node ID (exit 1)"
      PASS=$((PASS + 1))
    else
      echo "  ✗ a green-on-base new test must exit 1 naming the node ID (got exit $_rg_rc)"
      sed 's/^/      /' "$HOOK_OUT"
      FAIL=$((FAIL + 1))
    fi
    rm -rf "$_rg_dir"
  fi

  # (c) GREEN on base, MARKED: identical to (b) plus the documented marker with
  #     a reason. The exception must be honoured, or (b) has no way out.
  if _rg_new; then
    printf 'import pytest\n\nfrom calc import add\n\n\ndef test_add_existing():\n    assert add(5, 5) == 0\n\n\n@pytest.mark.characterization(reason="pinning add before the refactor")\ndef test_add_five_five():\n    assert add(5, 5) == 0\n' >"$_rg_dir/tests/test_calc.py"
    git -C "$_rg_dir" add -A && git -C "$_rg_dir" commit --quiet -m "add a characterization test" --no-verify  # scaffold-allow: test fixture
    _rg_rc=$(_rg_run "$_rg_dir" "$_rg_base")
    if [ "$_rg_rc" -eq 0 ] && grep -q 'exempt (characterization): tests/test_calc.py::test_add_five_five' "$HOOK_OUT"; then
      echo "  ✓ a green-on-base test marked @pytest.mark.characterization is exempted (exit 0)"
      PASS=$((PASS + 1))
    else
      echo "  ✗ a characterization-marked green-on-base test must be exempted and exit 0 (got exit $_rg_rc)"
      sed 's/^/      /' "$HOOK_OUT"
      FAIL=$((FAIL + 1))
    fi
    rm -rf "$_rg_dir"
  fi

  unset _rg_dir _rg_base _rg_rc
  unset -f _rg_fixture _rg_new _rg_run
fi
